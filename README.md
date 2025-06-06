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
    "query": "SELECT * FROM dataset WHERE age > {min_age} LIMIT 10",
    "params": {
        "min_age": 18
    }
}
```

## Production Deployment using Docker

### Troubleshooting: "exec format error"

If you see the error `exec /bin/sh: exec format error`, try these steps:

1. Check script permissions:
```bash
ls -l pre-start.sh
# Should show: -rwxr-xr-x 1 user user ... pre-start.sh
```

2. Fix permissions if needed:
```bash
chmod +x pre-start.sh
```

3. Check script contents:
```bash
cat pre-start.sh
# Verify the first line is: #!/bin/sh
```

4. Fix line endings (if using Windows):
```bash
# Install dos2unix if needed
apt-get update && apt-get install -y dos2unix

# Convert line endings
dos2unix pre-start.sh
```

5. Verify shell availability:
```bash
which sh
# Should return /bin/sh
```

6. Try running the script manually:
```bash
/bin/sh pre-start.sh
```

If the error persists after these steps, consider:
1. Using a simpler command in docker-compose.yml
2. Removing the pre-start script and running uvicorn directly
3. Checking for hidden characters in the script using `cat -A pre-start.sh`

## Production Deployment using Docker

### Automated Deployment with AWS CodePipeline

### Automated Deployment Options

<details>
<summary>💻 AWS Console Setup</summary>

1. **Create IAM Role for CodeDeploy**:
   1. Go to AWS Console -> IAM -> Roles
   2. Click "Create role"
   3. Select "CodeDeploy" as the service that will use this role
   4. Attach policies:
      - AWSCodeDeployRole
      - AmazonEC2ContainerRegistryReadOnly (Add this after creating the role):
        1. Go to IAM Console -> Roles
        2. Select "CodeDeployServiceRole"
        3. Click "Add permissions"
        4. Click "Attach policies"
        5. In the search box, type "AmazonEC2ContainerRegistryReadOnly"
        6. Select the policy
        7. Click "Add permissions"
   5. Name it "mquery-codeDeployServiceRole"
   6. Click "Create role"

2. **Create IAM Role for CodePipeline**:
   1. Go to AWS Console -> IAM -> Roles
   2. Click "Create role"
   3. Select "Trusted entity type": "Custom trust policy"
   4. Click "View policy document"
   5. Replace the policy with:
   ```json
    {
        "Version": "2012-10-17",
        "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
            "Service": "codepipeline.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
        ]
    }
   ```
   6. Click "Next: Permissions"
   7. Attach policies:
      - AWSCodePipelineFullAccess
      - AWSCodeDeployFullAccess
   8. Name it "mquery-codePipelineServiceRole"
   9. Click "Create role"

   **Note:** The role will automatically get the trust relationship needed for CodePipeline to assume this role.

3. **Create CodeDeploy Application**:
   1. Go to AWS Console -> CodeDeploy
   2. Click "Create application"
   3. Application name: "mquery-staging"
   4. Compute platform: "EC2/On-premises"
   5. Click "Create application"

4. **Create Deployment Group**:
   1. In CodeDeploy console, click "Create deployment group"
   2. Application name: Select "mquery-staging"
   3. Deployment group name: "mquery-staging-group"
   4. Service role: Select "CodeDeployServiceRole"
   5. Target: EC2 instances
   6. Environment configuration: "In-place deployment"
   7. Deployment configuration: "CodeDeployDefault.OneAtATime"
   8. Tag key: "Name"
   9. Tag value: "mquery-staging"
   10. Click "Create deployment group"

5. **Install CodeDeploy Agent on EC2**:
   1. SSH into your EC2 instance
   2. Run these commands:
   ```bash
   sudo apt-get update
   sudo apt-get install ruby
   sudo apt-get install wget
   cd /home/admin
   wget https://aws-codedeploy-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/latest/install
   chmod +x ./install
   sudo ./install auto
   ```
   3. Verify installation:
   ```bash
   sudo service codedeploy-agent status
   ```

6. **Create CodePipeline**:
   1. Go to AWS Console -> CodePipeline
   2. Click "Create pipeline"
   3. Choose category: "Deployment"
   4. Select template: "Push to ECR"
   5. Click "Next"
   6. Pipeline name: "mquery-staging-pipeline"
   7. Service role: "mquery-codePipelineServiceRole"
   8. Click "Next"
   9. Configure template:
      - ConnectionArn: Leave blank (we'll use GitHub connection)
      - FullRepositoryId: Leave blank (we'll use GitHub repository)
      - BranchName: Leave blank (we'll use GitHub branch)
      - DockerBuildContext: "." (use current directory)
      - DockerFilePath: "Dockerfile" (path to your Dockerfile)
      - ImageTag: "latest" (use latest tag)
      - RetentionPolicy: "Delete" (clean up resources when deleting stack)
   10. Click "Next"
   11. Click "Create pipeline"

   **Note:** We'll use the "Push to ECR" template because:
   - It provides the complete pipeline structure we need
   - It includes all three required stages:
     1. Source (GitHub)
     2. Build (CodeBuild - Docker build/tag/push)
     3. Deploy (CodeDeploy)
   - No modifications to the stages are needed after creation
   - This template is the most appropriate choice for our deployment needs

   **Important:** The pipeline is correctly configured with the ECR build stage using AWS CodeBuild. This stage handles:
   - Building the Docker image
   - Tagging it
   - Pushing it to ECR
   - No stages need to be removed or modified after creation
   - The pipeline uses AWS CodeBuild for the build stage, which is the recommended approach for ECR deployments

7. **Configure Source Stage**:
   - The source stage is automatically configured when using the "Push to ECR" template
   - It uses GitHub as the source provider
   - The template will automatically:
     1. Connect to your GitHub repository
     2. Set up the connection
     3. Configure the source stage with your repository
     4. Set the default branch to "backend"
     5. Use "CodePipeline default" as the output artifact format

   **Note:** All source stage configuration is handled automatically by the template. No manual steps are needed.

8. **Verify Pipeline Structure**:
   1. After pipeline creation, verify the pipeline has three stages:
      - Source (GitHub)
      - Build (CodeBuild - Docker build/tag/push)
      - Deploy (CodeDeploy)
   2. The build stage is essential as it:
      - Builds the Docker image
      - Tags it with the specified tag
      - Pushes it to ECR
   3. The deploy stage uses CodeDeploy to deploy to your EC2 instance

   **Note:** The pipeline structure is correct with three stages:
   1. Source (GitHub)
   2. Build (CodeBuild)
   3. Deploy (CodeDeploy)

9. **Test Pipeline**:
   1. First manual test:
      - Go to CodePipeline console
      - Click on your pipeline
      - Click "Release change" button
      - Monitor the pipeline execution in the console
      - Check each stage status:
        * Source: Should show "Succeeded"
        * Build: Should show "Succeeded"
        * Deploy: Should show "Succeeded"

   2. Automated test (recommended):
      - Make a small change to any file in your local repository
      - Commit and push to the `backend` branch:
        ```bash
        git add .
        git commit -m "Test change for pipeline"
        git push origin backend
        ```
      - The pipeline should automatically trigger
      - Monitor the pipeline execution in the console
      - Verify:
        * Pipeline starts automatically on push
        * All stages complete successfully
        * Application is deployed to EC2

   3. Verify deployment:
      ```bash
      # Check if application is running
      curl http://YOUR_EC2_IP:8000
      
      # Check if endpoints work
      curl http://YOUR_EC2_IP:8000/columns
      ```

   4. Verify ECR image:
      - Go to AWS ECR console
      - Find your repository
      - Verify the latest image tag was pushed

   **Note:** The pipeline should automatically trigger on any push to the `backend` branch. No manual "Release change" is needed after the first test.
    ```
</details>

<details>
<summary>💻 AWS CLI Setup</summary>

1. **Create IAM Roles**:
```bash
# Create CodeDeploy role
aws iam create-role --role-name CodeDeployServiceRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codedeploy.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

# Attach CodeDeploy permissions
aws iam attach-role-policy --role-name CodeDeployServiceRole --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
aws iam attach-role-policy --role-name CodeDeployServiceRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

# Create CodePipeline role
aws iam create-role --role-name CodePipelineServiceRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codepipeline.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'

# Attach CodePipeline permissions
aws iam attach-role-policy --role-name CodePipelineServiceRole --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineFullAccess
aws iam attach-role-policy --role-name CodePipelineServiceRole --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployFullAccess
```

2. **Create CodeDeploy Application**:
```bash
aws deploy create-application --application-name mquery-staging
```

3. **Create Deployment Group**:
```bash
aws deploy create-deployment-group \
    --application-name mquery-staging \
    --deployment-group-name mquery-staging-group \
    --service-role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/CodeDeployServiceRole \
    --deployment-config-name CodeDeployDefault.OneAtATime \
    --ec2-tag-filters Key=Name,Value=mquery-staging,Type=KEY_AND_VALUE \
    --auto-scaling-groups mquery-staging
```

4. **Create CodePipeline**:
```bash
aws codepipeline create-pipeline --cli-input-json '{
    "pipeline": {
        "name": "mquery-staging-pipeline",
        "roleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/CodePipelineServiceRole",
        "stages": [
            {
                "name": "Source",
                "actions": [
                    {
                        "name": "Source",
                        "actionTypeId": {
                            "category": "Source",
                            "owner": "AWS",
                            "provider": "CodeCommit",
                            "version": "1"
                        },
                        "runOrder": 1,
                        "configuration": {
                            "RepositoryName": "mquery-staging",
                            "BranchName": "main"
                        },
                        "outputArtifacts": [
                            {
                                "name": "SourceArtifact"
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Deploy",
                "actions": [
                    {
                        "name": "Deploy",
                        "actionTypeId": {
                            "category": "Deploy",
                            "owner": "AWS",
                            "provider": "CodeDeploy",
                            "version": "1"
                        },
                        "runOrder": 1,
                        "configuration": {
                            "ApplicationName": "mquery-staging",
                            "DeploymentGroupName": "mquery-staging-group"
                        },
                        "inputArtifacts": [
                            {
                                "name": "SourceArtifact"
                            }
                        ]
                    }
                ]
            }
        ],
        "artifactStore": {
            "type": "S3",
            "location": "codepipeline-ap-southeast-2-YOUR_ACCOUNT_ID"
        }
    }
}'
```

5. **Configure EC2 Instance**:
```bash
# Install CodeDeploy agent
sudo apt-get update
sudo apt-get install ruby
sudo apt-get install wget
cd /home/admin
wget https://aws-codedeploy-ap-southeast-2.s3.ap-southeast-2.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

# Verify installation
sudo service codedeploy-agent status
```

6. **Start Pipeline**:
```bash
aws codepipeline start-pipeline-execution --name mquery-staging-pipeline
```
</details>

Now, every time you push code to your repository:
1. CodePipeline will detect changes
2. Pull latest code from GitHub
3. Use CodeDeploy to deploy to your EC2 instance
4. Run the deployment script to update containers
5. Verify the deployment success

You can monitor the deployment progress in:
- CodePipeline console
- CodeDeploy console
- EC2 instance logs
- Your EC2 instance's health checks

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

1. Build and push to ECR:
```bash
# Stop any existing containers
docker-compose down

# Build with the correct image name
docker-compose build

# Tag the image for ECR
docker tag mquery-backend:latest 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest

# Login to ECR
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com

# Push to ECR
docker push 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com/dev/mquery-backend:latest
```

2. On your EC2 instance:
```bash
# SSH into EC2
ssh -i your-key.pem ubuntu@your-ec2-public-ip

# Navigate to your project directory
cd mquery-staging

# Login to ECR
aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 905418328516.dkr.ecr.ap-southeast-2.amazonaws.com

# Pull latest image and restart containers
docker-compose pull
docker-compose up -d

# Verify everything is running

1. Check container status:
```bash
docker-compose ps
```
You should see the app container running with status "Up"

2. Check logs for any errors:
```bash
docker-compose logs -f
```
Look for successful startup messages and no errors

3. Test the API endpoints:
```bash
# Test root endpoint
curl http://localhost:8000
# Should return: {"message": "DuckDB Query API is running"}

# Test healthcheck
curl http://localhost:8000/health
# Should return 200 status code

# Test columns endpoint
curl http://localhost:8000/columns
# Should return list of columns
```

4. Testing from Anywhere

First, get your EC2 instance's public IP:
```bash
curl http://169.254.169.254/latest/meta-data/public-ipv4
```

Make sure port 8000 is open in your EC2 security group:
1. Go to AWS Console -> EC2 -> Security Groups
2. Find your EC2 instance's security group
3. Add inbound rule:
   - Type: Custom TCP
   - Port: 8000
   - Source: 0.0.0.0/0 (or your specific IP range)

Then you can test from any computer:

```bash
# Replace YOUR_EC2_IP with your actual EC2 public IP

# Note: Use HTTP (not HTTPS) since we're running the FastAPI server directly
# HTTPS setup requires additional configuration with a reverse proxy

# Test root endpoint, e.g 16.176.218.132
curl http://YOUR_EC2_IP:8000

# Test columns endpoint
curl http://YOUR_EC2_IP:8000/columns

# Test query endpoint with POST request
curl -X POST http://YOUR_EC2_IP:8000/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT * FROM dataset LIMIT 1",
    "params": {}
  }'
```

# If you need to stop the service
docker-compose down

# If you need to restart the service
docker-compose restart

# If you need to view container details
docker ps -a

# If you need to view container logs
docker logs mquery-staging_app_1
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
