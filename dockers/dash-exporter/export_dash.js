const { chromium } = require('playwright-core');
const express = require('express');
const cron = require('node-cron');
const axios = require('axios');
const FormData = require('form-data');
const fs = require('fs');
const nodemailer = require('nodemailer');
const path = require('path');

const app = express();
const port = 3010;
const EXPORTS_DIR = 'exports';
const LOGS_DIR = 'logs';
const LOG_FILE = path.join(LOGS_DIR, 'export.log');
const CONFIG_PATH = path.join(__dirname, 'schedules.json');

// Подготовка папок
[EXPORTS_DIR, LOGS_DIR].forEach(dir => {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

// --- ЛОГИРОВАНИЕ ---
function writeLog(dashboardId, format, type, status, details = '') {
    const timestamp = new Date().toLocaleString('ru-RU');
    const logEntry = `[${timestamp}] | ID: ${dashboardId.substring(0, 8)} | Format: ${format} | Type: ${type} | Status: ${status} | ${details}\n`;
    fs.appendFile(LOG_FILE, logEntry, (err) => { if (err) console.error('Log error:', err); });
    console.log(logEntry.trim());
}

// --- ПОЧТА ---
const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT), 
    secure: parseInt(process.env.SMTP_PORT) === 465, // True для 465, false для 587
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
    },
    // Добавляем этот блок для обхода проблем с сертификатами хостинга
    tls: {
        rejectUnauthorized: false,
        minVersion: 'TLSv1.2'
    },
    debug: true, // Включает детальный вывод в консоль
    logger: true // Логирует процесс в терминал
});

// --- УВЕДОМЛЕНИЯ ---
async function sendNotifications(filePath, dashboardId, format, fileSize) {
    const shortId = dashboardId.substring(0, 8);
    const sizeMB = (fileSize / (1024 * 1024)).toFixed(2);
    
    if (process.env.TELEGRAM_BOT_TOKEN && process.env.TELEGRAM_CHAT_ID) {
        const form = new FormData();
        form.append('chat_id', process.env.TELEGRAM_CHAT_ID);
        form.append('caption', `📊 Отчет (${format.toUpperCase()}) #${shortId}\n📦 Размер: ${sizeMB} MB`);
        form.append('document', fs.createReadStream(filePath));
        await axios.post(`https://api.telegram.org/bot${process.env.TELEGRAM_BOT_TOKEN}/sendDocument`, form, { headers: form.getHeaders() }).catch(e => console.error('TG Error:', e.message));
    }
    if (process.env.EMAIL_TO) {
        await transporter.sendMail({
            from: `"Metabase Reports" <${process.env.SMTP_USER}>`,
            to: process.env.EMAIL_TO,
            subject: `Metabase ${format.toUpperCase()} отчет: ${shortId} (${sizeMB} MB)`,
            attachments: [{ path: filePath }]
        }).catch(e => console.error('Email Error:', e.message));
    }
}

// --- ЯДРО ГЕНЕРАЦИИ ---
async function generateExport(dashboardId, format = 'pdf', type = 'Manual') {
    format = format.toLowerCase();
    const selenoidHost = process.env.SELENOID_URL || 'http://selenoid:4444';
    const metabaseURL = process.env.METABASE_INTERNAL_URL || 'http://metabase:3000';
    
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `dashboard_${dashboardId.substring(0, 8)}_${timestamp}.${format}`;
    const filePath = path.join(EXPORTS_DIR, fileName);

    let browser;

    try {
        console.log(`[${dashboardId.substring(0, 8)}] 1. Запрос сессии Selenoid...`);
        const sessionRes = await axios.post(`${selenoidHost}/wd/hub/session`, {
            desiredCapabilities: {
                browserName: "chrome",
                version: "125.0",
                "selenoid:options": { enableVNC: true, name: `Export ${dashboardId.substring(0,8)}` }
            }
        });

        const sessionId = sessionRes.data.sessionId || sessionRes.data.value.sessionId;
        const wsUrl = selenoidHost.replace('http://', 'ws://') + '/devtools/' + sessionId;
        
        browser = await chromium.connectOverCDP(wsUrl);
        const context = await browser.newContext();
        const page = await context.newPage();
        
        const publicUrl = `${metabaseURL}/public/dashboard/${dashboardId}#fullscreen`;
        console.log(`[${dashboardId.substring(0, 8)}] 2. Загрузка дашборда...`);
        await page.goto(publicUrl, { waitUntil: 'networkidle', timeout: 90000 });

        // --- ЭТАП ПОДГОТОВКИ (Универсальный для PNG и PDF) ---
        console.log(`[${dashboardId.substring(0, 8)}] 3. Подготовка отображения...`);
        
        // Ждем появления сетки
        await page.waitForSelector('.react-grid-layout', { state: 'visible', timeout: 30000 });

        // Прокрутка для активации графиков
        await page.evaluate(async () => {
            const scrollTarget = document.querySelector('main') || document.body;
            scrollTarget.scrollBy(0, 2000);
            await new Promise(r => setTimeout(r, 1000));
            scrollTarget.scrollTo(0, 0);
        });

        // Ждем отрисовку данных
        await page.waitForTimeout(10000);

        // Расчет высоты и разворачивание контейнеров
        const dimensions = await page.evaluate(() => {
            const grid = document.querySelector('.react-grid-layout');
            const fix = (el) => {
                if (!el) return;
                el.style.setProperty('height', 'auto', 'important');
                el.style.setProperty('overflow', 'visible', 'important');
                el.style.setProperty('max-height', 'none', 'important');
            };

            fix(document.documentElement);
            fix(document.body);
            fix(document.querySelector('main'));
            fix(document.getElementById('Dashboard-Parameters-And-Cards-Container'));

            return {
                height: grid ? grid.scrollHeight + 200 : 2000,
                width: 1300
            };
        });

        // Устанавливаем вьюпорт один раз для обоих форматов
        await page.setViewportSize({ 
            width: 1300, 
            height: dimensions.height 
        });

        // Прячем лишние элементы интерфейса
        await page.evaluate(() => {
            const style = document.createElement('style');
            style.innerHTML = `
                header, .FixedHeader, .DashboardHeader, .Nav-navbar, 
                .saving-dom-image-display-none, .react-resizable-handle,
                button, [data-testid="export-as-pdf-button"] { 
                    display: none !important; 
                }
                ::-webkit-scrollbar { display: none !important; }
            `;
            document.head.appendChild(style);
        });

        await page.waitForTimeout(3000); // Даем время CSS примениться

        // --- ЭТАП ЭКСПОРТА ---
        let finalFileSize = 0;

        if (format === 'pdf') {
            console.log(`[${dashboardId.substring(0, 8)}] 4. Печать PDF (Native)...`);
            await page.emulateMedia({ media: 'screen' });
            await page.pdf({
                path: filePath,
                printBackground: true,
                width: '1300px',
                height: dimensions.height + 'px',
                pageRanges: '1',
                preferCSSPageSize: true,
                margin: { top: 0, right: 0, bottom: 0, left: 0 }
            });
        } else {
            console.log(`[${dashboardId.substring(0, 8)}] 4. Снимок PNG...`);
            await page.screenshot({ 
                path: filePath, 
                fullPage: true,
                animations: 'disabled'
            });
        }

        finalFileSize = fs.statSync(filePath).size;
        await sendNotifications(filePath, dashboardId, format, finalFileSize).catch(() => {});
        writeLog(dashboardId, format, type, 'Success', `Size: ${(finalFileSize / 1024).toFixed(2)} KB`);
        
        return { fileName, filePath, fileSize: finalFileSize };

    } catch (err) {
        writeLog(dashboardId, format, type, 'Failed', err.message);
        throw err;
    } finally {
        if (browser) await browser.close();
    }
}

// --- API & CRON ---
app.get('/export', async (req, res) => {
    const { id, format = 'pdf' } = req.query;
    if (!id) return res.status(400).send({ error: 'Нужен UUID' });
    try {
        const result = await generateExport(id, format, 'API Request');
        res.status(200).send({ status: 'success', file: result.fileName });
    } catch (error) {
        res.status(500).send({ status: 'error', message: error.message });
    }
});

function loadSchedules() {
    if (!fs.existsSync(CONFIG_PATH)) return;
    try {
        const schedules = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
        schedules.forEach(task => {
            cron.schedule(task.cron, () => generateExport(task.id, task.format || 'pdf', 'Auto'), { timezone: "Asia/Aqtobe" });
        });
    } catch (e) { console.error('Schedule error:', e.message); }
}

loadSchedules();
app.listen(port, () => console.log(`🚀 Exporter ready on port ${port}`));