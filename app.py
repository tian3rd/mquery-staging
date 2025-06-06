from datetime import datetime

import duckdb
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any

app = FastAPI(title="DuckDB Query API")

# Connect to DuckDB (in-memory)
conn = duckdb.connect(database=':memory:')

# Load the parquet file into DuckDB
try:
    conn.execute("CREATE TABLE dataset AS SELECT * FROM read_parquet('YouthRisk2007.pq')")
except Exception as e:
    raise HTTPException(status_code=500, detail=f"Failed to load data: {str(e)}")

class QueryRequest(BaseModel):
    query: str
    params: Dict[str, Any] = {}

class QueryResponse(BaseModel):
    result: List[Dict[str, Any]]
    columns: List[str]

@app.get("/")
def read_root():
    return {"message": "DuckDB Query API is running"}

@app.get("/columns")
def get_columns():
    """Get list of all columns in the dataset"""
    try:
        result = conn.execute("SELECT column_name FROM information_schema.columns WHERE table_name = 'dataset'").fetchall()
        return {"columns": [col[0] for col in result]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
def health_check():
    return {"status": "ok", "timestamp": datetime.now().isoformat()}

@app.post("/query")
def execute_query(request: QueryRequest):
    """Execute a SQL query against the dataset"""
    try:
        # Format query with parameters
        formatted_query = request.query.format(**request.params)
        
        # Execute query
        result = conn.execute(formatted_query).fetchall()
        
        # Get column names
        columns = [desc[0] for desc in conn.description]
        
        # Convert result to list of dicts
        response = [
            {col: value for col, value in zip(columns, row)}
            for row in result
        ]
        
        return QueryResponse(result=response, columns=columns)
    
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Query execution failed: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
