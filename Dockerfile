# استخدم صورة رسمية من Docker
FROM docker:latest

# تثبيت docker-compose
RUN apk add --no-cache docker-compose

# نسخ ملفات التهيئة داخل الحاوية
WORKDIR /app
COPY pwd.yml /app/docker-compose.yml

# تشغيل Docker Compose عند بدء الحاوية
CMD ["sh", "-c", "docker compose -f pwd.yml up -d && tail -f /dev/null"]
