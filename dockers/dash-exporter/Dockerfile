FROM node:18-slim
WORKDIR /app
COPY package.json .
RUN npm install
COPY export_dash.js .
COPY schedules.json .
RUN mkdir exports logs
CMD ["node", "export_dash.js"]