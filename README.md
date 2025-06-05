# DuckDB Query API

A FastAPI backend for querying DuckDB database with a Parquet dataset.

## Local Development

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

## Production Deployment using Docker

### Prerequisites

1. Docker and Docker Compose installed on your system
2. AWS CLI configured with appropriate permissions
3. An AWS ECR repository created
4. An EC2 instance with Docker installed
5. IAM Role with ECR permissions attached to your EC2 instance

#### Setting Up IAM Role for ECR Access

1. **Create IAM Role**:
   - Go to AWS Console -> IAM -> Roles
   - Click "Create role"
   - Select "EC2" as the service that will use this role
   - Click "Next: Permissions"

2. **Add ECR Permissions**:
   - Choose one of these options:
     - For read-only access: `AmazonEC2ContainerRegistryReadOnly`
     - For full access (read/write): `AmazonEC2ContainerRegistryFullAccess`
     - For minimal permissions: Use the custom policy below

3. **Custom Policy** (optional - only needed if you don't use the managed policies):
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetRepositoryPolicy",
                "ecr:DescribeRepositories",
                "ecr:ListImages",
                "ecr:DescribeImageScanFindings",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        }
    ]
}
```

**Note**: If you use `AmazonEC2ContainerRegistryFullAccess`, you don't need to create the custom policy. The managed policy already includes all necessary permissions for ECR.

4. **Attach the Role to Your EC2 Instance**:
   - Go to EC2 Console
   - Select your EC2 instance
   - Click "Actions" -> "Security" -> "Modify IAM role"
   - Select the role you created
   - Click "Update IAM role"

5. **Verify IAM Role**:
```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@your-ec2-public-ip

# Verify IAM role
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

6. **Additional Security Considerations**:
   - Use the minimum set of permissions required
   - Consider using resource-level permissions instead of `*` if possible
   - Regularly review and audit IAM roles and permissions
   - Consider using AWS Organizations SCPs for additional security controls

### Deployment Steps

#### 1. Build and Push to ECR

```bash
# Build the optimized Docker image locally
docker build -t mquery-backend .

# Tag it for ECR
docker tag mquery-backend:latest 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest

# Login to ECR
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com

# Push to ECR
docker push 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest
```

### AWS ECR Login Details

For AWS ECR login:

1. Username: Always use "AWS" (case-sensitive)
2. Password: AWS CLI generates a temporary password using `get-login-password`
3. Server: Use your full ECR repository URL

Example:
```bash
# For your repository
YOUR_AWS_ACCOUNT_ID=905418328516
REGION=ap-southeast-2
REPO_NAME=dev/mquery-backend

# Login command
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $YOUR_AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Push command
docker push $YOUR_AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
```

Note:
- The login credentials are temporary (12 hours)
- You'll need to run the login command again if you need to push images after that time
- Make sure your AWS CLI is configured with the correct credentials and permissions

#### 2. Deploy to EC2 (t3.small optimized)

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@your-ec2-public-ip

# Clone the repository
git clone your-repo-url

cd mquery-staging

# Run with docker-compose (optimized for t3.small)
docker-compose up -d
```

### Using Docker Compose

The project includes a `docker-compose.yml` file optimized for t3.small instances.

#### Development Mode

```bash
# Build and run locally
docker-compose up --build -d

# If you get "mounts denied" error:
# Option 1 - Add project directory to Docker Desktop's shared folders:
#   1. Open Docker Desktop
#   2. Go to Settings -> Resources -> File Sharing
#   3. Add your project directory (/Users/tian/Documents/mquery-staging)
#   4. Click Apply & Restart

# Option 2 - Create the data directory:
mkdir -p data
docker-compose up --build -d

# If you need to rebuild after changing requirements.txt:
docker-compose down
docker-compose up --build -d

# View logs
docker-compose logs -f

# Stop the containers
docker-compose down

# View container status
docker-compose ps

# Alternatively, you can run directly with docker:
docker build -t mquery-backend .
docker run -d -p 8000:8000 mquery-backend
```

#### Production Mode

1. On your EC2 instance:
```bash
# SSH into EC2
ssh -i your-key.pem ubuntu@your-ec2-public-ip

# Navigate to your project directory
cd mquery-staging

# Pull latest image and restart containers
docker-compose pull
docker-compose up -d

# Verify everything is running
docker-compose ps  # Check container status
docker-compose logs -f  # View logs
curl http://localhost:8000  # Test the API

# If you need to stop the service
docker-compose down
```

### Production Considerations

1. **Security**
   - Set up HTTPS using AWS Certificate Manager
   - Configure security groups to only allow traffic on port 8000
   - Consider using AWS Secrets Manager for sensitive configurations

2. **Monitoring**
   - Set up CloudWatch Logs for application logging
   - Configure CloudWatch Alarms for monitoring
   - Set up AWS X-Ray for tracing

3. **Backup Strategy**
   - Set up automated backups of your Parquet file
   - Consider using AWS S3 for data storage and backups

4. **Performance**
   - Use an Application Load Balancer (ALB) in front of your EC2 instance
   - Monitor CPU and memory usage
   - Consider horizontal scaling if needed

5. **Maintenance**
   - The `restart: always` policy ensures the container restarts automatically
   - Use `docker-compose logs` to monitor container output
   - Regularly update the Docker image with security patches

## Environment Variables

The application supports the following environment variables:

- `PORT`: Port to run the application on (default: 8000)
- `HOST`: Host to bind to (default: 0.0.0.0)
- `LOG_LEVEL`: Logging level (default: info)

## Troubleshooting

1. If the container fails to start:
   ```bash
   docker-compose logs -f
   ```

2. To check container status:
   ```bash
   docker-compose ps
   ```

3. To view container logs:
   ```bash
   docker-compose logs app
   ```
