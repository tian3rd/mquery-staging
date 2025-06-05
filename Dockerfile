FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --no-warn-script-location -r requirements.txt

# Copy application code
COPY app.py .
COPY YouthRisk2007.pq ./data/
COPY pre-start.sh .

# Make pre-start script executable
RUN chmod +x pre-start.sh

# Create data directory
RUN mkdir -p /app/data && \
    chown -R 1000:1000 /app/data

# Expose port
EXPOSE 8000

# Start the application with uvicorn
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
