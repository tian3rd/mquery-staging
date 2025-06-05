# DuckDB Query API

A FastAPI backend for querying DuckDB database with a Parquet dataset.

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Run the API:
```bash
python app.py
```

The API will be available at http://localhost:8000

## API Endpoints

- `GET /` - Health check endpoint
- `GET /columns` - Get list of all columns in the dataset
- `POST /query` - Execute custom SQL queries

### Query Endpoint Example

Send a POST request to `/query` with the following JSON body:
```json
{
    "query": "SELECT * FROM youth_risk WHERE age > {min_age} LIMIT 10",
    "params": {
        "min_age": 18
    }
}
```

## Deployment Options

1. Local Development - Run directly on your machine
2. Docker - Containerize the application
3. Cloud Hosting - Deploy to services like:
   - AWS EC2
   - Heroku
   - DigitalOcean
   - Render

For production deployment, consider:
- Setting up proper authentication
- Adding rate limiting
- Implementing proper error handling
- Adding logging
- Setting up proper monitoring
