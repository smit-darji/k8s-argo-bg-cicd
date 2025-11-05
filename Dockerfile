# Use official Python slim image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy application files
COPY index.html push_logs.py ./

# Install dependencies
RUN pip install --no-cache-dir flask requests

# Expose port (match Flask app port)
EXPOSE 80

# Set default command to run your app
CMD ["python", "push_logs.py"]
