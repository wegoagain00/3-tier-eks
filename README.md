# 🚀 DevOps Project: Deploying a three tier app on AWS EKS (EKS, EC2, RDS, Github Actions, ECR, ALB, Route53, OIDC, IAM)

## 🏗 Architecture
![arch](/images/three-tier-eks.jpeg)

## 🧠 About the Project
In this project, we will deploy a three-tier application on AWS EKS (Elastic Kubernetes Service). The application consists of a React frontend, Flask backend and a RDS PostgreSQL database. We will use Docker to containerize the application, Github Actions and ECR to implement CI and Kubernetes to orchestrate the deployment on EKS.

To make the application publicly accessible, I'll implement an AWS load balancer controller which will provision an ALB (Application Load Balancer) through Kubernetes ingress resources. In addition Kubernetes secrets will be used to store sensitive information such as database credentials and ConfigMap will be used to store non-sensitive configuration data.

Before deploying the backend service, I'll run database migrations using a Kubernetes Job, ensuring the schema is properly initialized. To simplify database connectivity, I'll utilize an External Service for the RDS instance, leveraging Kubernetes' DNS-based service discovery to maintain clean application configuration.

***(note: EKS charges .10p/hour so ensure it's deleted when you complete project) I'VE WARNED YOU :D***

The reason why we are using Kubernetes is because its a powerful, popular tool for running large-scale, containerized applications or microservices. Its a must in the DevOps world and is used by many companies to manage their applications in production. Kubernetes provides features like automatic scaling, load balancing, and self-healing, making it easier to deploy and manage applications in a cloud environment.

Setting up Kubernetes on AWS can be complex, but using EKS simplifies the process by providing a managed Kubernetes service. EKS handles the underlying infrastructure, allowing us to focus on deploying and managing our applications without worrying about the complexities of setting up and maintaining a Kubernetes cluster from scratch.

In EKS, youre provided with 3 options on how to run your workloads:
- ***Managed Node Groups***: EKS automatically provisions and manages the EC2 instances that run your Kubernetes workloads. This is the most common and recommended option for running workloads on EKS.
- ***Self-Managed Node Groups***: You can create and manage your own EC2 instances to run your Kubernetes workloads. This option gives you more control over the underlying infrastructure but requires more management overhead.
- ***Fargate Nodes***: EKS Fargate allows you to run your Kubernetes workloads without managing the underlying EC2 instances. Fargate automatically provisions and scales the compute resources needed to run your containers, making it a serverless option for running workloads on EKS. Note: You cant use persistent volumes with Fargate, so if you need to store data that persists beyond the lifecycle of a pod, you should use managed node groups or self-managed node groups.

We will keep it simple and use ***Managed Node Groups*** with `eksctl` for this project, as it provides a good balance between ease of use and control over the underlying infrastructure.

## Prerequisites
I'll assume you have basic knowledge of Docker, Kubernetes, and AWS services. you will need to install ***eksctl, aws cli, kubectl, helm and docker*** on your local machine.

You will also need an AWS account with the necessary permissions to create EKS clusters, EC2 instances, and other resources.


## 🚀 Getting Started

> ⚠️ **NOTE**: For each section I will actually recommend reseraching each command you input to understand what it does and why its needed. This will help you understand the process better and make it easier to troubleshoot any issues that may arise. Use documentation then AI as long as you understand what its doing and why its needed.

Lets start by setting up the EKS cluster and deploying the application. To create the EKS cluster, we will use `eksctl`, a command-line tool that simplifies the process of creating and managing EKS clusters. (Remember to configure your AWS CLI with your credentials and region before running the commands and ensure you have the necessary permissions to create EKS clusters and other resources in your AWS account.)

```bash
# Eksctl command to build an EKS cluster with a managed node group
# with 2 nodes(min:1, max: 3 nodes as autoscaling)
eksctl create cluster \
  --name three-tier-react \
  --region eu-west-2 \
  --version 1.31 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed
```
![EKS Cluster Nodes](/images/img-1.png)

A cloud formation stack is what runs in the backend to configure these resources.\
This `eksctl` command creates an Amazon EKS (Elastic Kubernetes Service) cluster in AWS with the following specifications:

**Cluster Details:**
- **Name**: `three-tier-react`
- **Region**: `eu-west-2` (Europe - London)
- **Kubernetes Version**: `1.31`

**Node Group Configuration:**
- **Node Group Name**: `standard-workers`
- **Instance Type**: `t3.medium` (2 vCPUs, 4GB RAM)
- **Initial Node Count**: 2 nodes
- **Minimum Nodes**: 1 (for auto-scaling)
- **Maximum Nodes**: 3 (for auto-scaling)
- **Managed**: Uses AWS-managed node groups (AWS handles node provisioning, updates, and lifecycle management)

**What Gets Created:**
- An EKS control plane (master nodes managed by AWS)
- A VPC with public and private subnets across multiple availability zones
- An Internet Gateway and NAT Gateways for networking
- Security groups with appropriate rules
- IAM roles and policies for the cluster and nodes
- A managed node group with 2 t3.medium EC2 instances
- Auto Scaling Group configured to scale between 1-3 nodes
- Integration with AWS Load Balancer Controller and other AWS services

The `--managed` flag means AWS will automatically handle node updates, security patches, and replacement of unhealthy nodes. This is typically the recommended approach for production workloads as it reduces operational overhead.

It can take 10-20 minutes to create the cluster, so be patient. Once the cluster is created, you can verify it by running:

```bash
# Check the status of the EKS cluster
aws eks list-clusters --region eu-west-2
```
Now to access the cluster, we need to check if we are connected to the kubeconfig file. This allows `kubectl` to communicate with the EKS cluster.
```bash
# Get the current context
kubectl config current-context
```
If not run:

```bash
# Update kubeconfig to use the new EKS cluster
aws eks update-kubeconfig --name <cluster-name> --region eu-west-2
# Get the current context
kubectl config current-context
```
![EKS Cluster Nodes](/images/img-2.png)

Now run these commands to ensure you can see the nodes in your cluster:

```bash
# Check the nodes in the cluster
kubectl get namespaces #list all namespaces
kubectl get node #list all nodes
kubectl get pod -A #list all pods in all namespaces
kubectl get services -A #list all services in all namespaces
```

![EKS Cluster Nodes](/images/img-3.png)

Hopefully should all be up and running.

For this project we are using a React frontend, a Flask backend that connects to a PostgreSQL database.

### Creating RDS PostgreSQL Database
The PostgreSQL RDS instance will be in the same VPC as the EKS cluster, allowing the application to connect to it securely. EKS created private subnets for the cluster, so we will use those subnets to deploy the RDS instance.

You can directly check for VPC ID and Private Subnet IDs in the AWS console or use the following command: (this will be used later to create a subnet group for the RDS instance)

```bash
# Get the VPC ID and Private Subnet IDs for the EKS cluster (stores VPC ID in VPC_ID variable)
VPC_ID=$(aws eks describe-cluster \
  --name three-tier-react \
  --region eu-west-2 \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)
# Get the Private Subnet IDs for the EKS cluster
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" \
  --region eu-west-2 \
  --output text

# create a subnet group for the RDS instance (replace the subnet IDs with your own)
aws rds create-db-subnet-group \
  --db-subnet-group-name three-tier-react-db-subnet-group \
  --db-subnet-group-description "Subnet group for three-tier-react RDS instance" \
  --subnet-ids <your-subnet-id> <your-subnet-id> <your-subnet-id> \
  --region eu-west-2
```
![](/images/img-4.png)

Lets create a security group for the RDS instance. This security group will allow inbound traffic from the EKS cluster's worker nodes on the PostgreSQL port (5432).

```bash
# Create a security group for the RDS instance
aws ec2 create-security-group \
  --group-name three-tier-react-rds-security-group \
  --description "Security group for RDS instance three-tier-react" \
  --vpc-id $VPC_ID \
  --region eu-west-2
```
![](/images/img-5.png)

Now the security group is created, we need to allow inbound traffic from the EKS cluster's worker nodes on the PostgreSQL port (5432).
```bash
# Get the security group ID of rds-security-group
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=three-tier-react-rds-security-group" "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[0].GroupId" \
  --output text \
  --region eu-west-2)
# Get the security group ID of the EKS cluster's worker nodes
EKS_SG_ID=$(aws eks describe-cluster \
  --name three-tier-react \
  --region eu-west-2 \
  --query "cluster.resourcesVpcConfig.securityGroupIds[0]" \
  --output text)
# Allow inbound traffic from the EKS cluster's worker nodes on the PostgreSQL port (5432)
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 5432 \
  --source-group $EKS_SG_ID \
  --region eu-west-2
```

![](/images/img-6.png)

Now to create the RDS instance, we will use the `aws rds create-db-instance` command. This command will create a PostgreSQL database instance in the VPC and private subnets we created earlier. (change the password to your own, also the subnet group name)

```bash
aws rds create-db-instance \
  --db-instance-identifier three-tier-react-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 15 \
  --master-username postgresadmin \
  --master-user-password <makethisyourpassword> \
  --allocated-storage 20 \
  --vpc-security-group-ids $RDS_SG_ID \
  --db-subnet-group-name three-tier-react-db-subnet-group \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --multi-az \
  --storage-type gp2 \
  --region eu-west-2
```
Change both `--master-username` from admin and the `--master-user-password` to a secure password of your choice. \
For security: Storing secrets like the DB password in AWS Secrets Manager or a Kubernetes Secret instead of hardcoding them would be recommended.

![](/images/img-7.png)

It may take a while but you will see it getting created, go to AWS RDS Console and check the status of the DB instance.
![](/images/img-8.png)

---

***Now its time to create our three-tier application. As you can see the frontend and backend are in this repository. I will be implementing CI using GitHub Actions and ECR so the image can be hosted on AWS***

You can clone this repository to get the code for the application:
```bash
git clone https://github.com/wegoagain00/3-tier-eks.git
```

Before we begin lets set up OIDC for the connection between our AWS and GitHub Actions. This allows our GitHub Actions workflow to authenticate with AWS using short-lived tokens, completely removing the need to store any AWS keys in GitHub secrets.

1. Go to IAM -> Identity providers and add a new provider.
2. Choose OpenID Connect as option.
3. For the "Provider URL", use `https://token.actions.githubusercontent.com`.
4. For the "Audience", use `sts.amazonaws.com`.
5. Go to the Identity provider and select 'Assign Role', then 'Create an IAM Role', select 'web identity', on audience use `sts.amazonaws.com`. On Github organisation enter your github username, also on Github repository enter the name of the repository, also git branch on `main` then press next.
6. On permissions attach the `AmazonEC2ContainerRegistryPowerUser`, to allow it to push images to ECR. Press next.
7. Give the role a name like "GitHubActionsECR". and then create the role

![](/images/img-9.png)
![](/images/img-10.png)
![](/images/img-11.png)

Now we have the permissions we will need to create the ECR repository for these images to be pushed to.
1. Go to ECR on AWS console and create a new repository for each image we will be pushing to ECR.

![](/images/img-12.png)

2. Do the same for the backend image.
![](/images/img-13.png)

Now this repository will have it but we will create this following folder `.github/workflows/ci.yml`. This will contain the CI pipeline for the application. It will push our images to the ECR.

Use the following ci.yml file and replace the following with your own:
`AWS_REGION`: The AWS region where your ECR repositories are located (e.g., us-west-2).
`ECR_REPOSITORY_FRONTEND`: The name of the ECR repository you created for your frontend image.
`ECR_REPOSITORY_BACKEND`: The name of the ECR repository for your backend image.
`IAM_ROLE_ARN`: The full ARN of the IAM role you just created. It will look like
arn:aws:iam::123456789012:role/YourRoleName.




### Namespace
***The first thing we will be doing is creating the Kubernetes namespace, we need this to isolate group of resources. It gives you a virtual cluster for you to work within, usually needed when working in teams.***

`kubectl apply -f namespace.yaml` will create the namespace named ***three-tier-app-eks*** for the application. if you do `kubectl get namespaces` you should see the namespace created, if you dont it'll be created in the default namespace.

### RDS service
***Time to create a service for our RDS instance***

 Add your RDS endpoint in the `externalName` field. You can find your RDS endpoint in the AWS console under the RDS instance details. Then apply the service manifest: `kubectl apply -f database-service.yaml`


```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-db
  namespace: 3-tier-app-eks
  labels:
    service: database
spec:
  type: ExternalName
  externalName: tawfiq-db.cto44ogqocij.eu-west-2.rds.amazonaws.com
  ports:
  - port: 5432
```

Now the DNS name for RDS using service discovery is set up, we can use it in our application pods to connect to the database. The format is `service-name.namespace.svc.cluster.local`, so in this case it would be `postgres-db.3-tier-app-eks.svc.cluster.local`. This service is needed to allow the application pods to connect to the RDS instance using a DNS name instead of the full RDS endpoint URL. This makes it easier to manage and change the database connection details without modifying the application code.

To test we can run a temporary pod in the same namespace and try to connect to the RDS instance using the DNS name:

```bash
kubectl run -i --tty pg-client --image=postgres --namespace=3-tier-app-eks -- bash
# Inside the pod, try to connect to the RDS instance
#the name wegoagain is the username we set when creating the RDS instance change it to your username
psql -h postgres-db -p 5432 -U wegoagain -d postgres
```
Itll ask for the password, enter the password you set when creating the RDS instance. If you see a prompt like `postgres=#`, then you have successfully connected to the RDS instance. Dont forget to exit the pod when done by typing `exit` and then `exit` again.

To delete the temporary pod, run:

```bash
kubectl delete pod pg-client --namespace=3-tier-app-eks
```

![](/images/img-7.png)

### Why use AWS RDS vs Containerized PostgreSQL

| Aspect                     | AWS RDS PostgreSQL                                                                                                   | Containerized PostgreSQL                                                                        |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| **High Availability**      | ✅ Multi-AZ automatic failover<br>✅ 99.95% uptime SLA<br>✅ Cross-region read replicas                                 | ❌ Single point of failure<br>❌ Manual HA setup required<br>❌ Complex multi-node configuration   |
| **Backup & Recovery**      | ✅ Automated daily backups<br>✅ Point-in-time recovery (35 days)<br>✅ Cross-region backup replication                 | ❌ Manual backup processes<br>❌ Complex recovery procedures<br>❌ Additional storage overhead     |
| **Operational Management** | ✅ Automatic security patching<br>✅ Managed minor version upgrades<br>✅ Built-in monitoring (CloudWatch)              | ❌ Manual patch management<br>❌ Self-managed updates<br>❌ Custom monitoring setup required       |
| **Security**               | ✅ Encryption at rest (KMS)<br>✅ Encryption in transit (SSL/TLS)<br>✅ VPC isolation<br>✅ IAM database authentication  | ⚠️ Manual encryption setup<br>⚠️ Complex secret management<br>⚠️ Additional security configuration |
| **Performance**            | ✅ Provisioned IOPS<br>✅ Optimized database instances<br>✅ RDS Proxy for connection pooling<br>✅ Performance Insights | ❌ Limited by node resources<br>❌ Manual performance tuning<br>❌ Complex connection pooling      |
| **Scalability**            | ✅ Easy vertical scaling<br>✅ Read replicas for horizontal scaling<br>✅ Storage auto-scaling                          | ❌ Node resource constraints<br>❌ Complex replica setup<br>❌ Manual storage management           |
| **Cost**                   | ✅ Pay-as-you-use pricing<br>✅ Reserved instance discounts<br>✅ No operational overhead                               | ❌ Need multiple nodes for HA<br>❌ Additional storage costs<br>❌ Higher operational costs        |
| **Compliance**             | ✅ SOC, PCI DSS, HIPAA certified<br>✅ AWS compliance inheritance                                                      | ❌ Manual compliance implementation<br>❌ Additional audit requirements                           |
| **Disaster Recovery**      | ✅ Automated cross-AZ replication<br>✅ Cross-region disaster recovery<br>✅ Automated failover                         | ❌ Manual DR setup<br>❌ Complex failover procedures<br>❌ Risk of data loss                       |
| **Development Speed**      | ✅ Quick provisioning<br>✅ Ready-to-use service<br>✅ Focus on application logic                                       | ❌ Complex Kubernetes setup<br>❌ YAML configuration overhead<br>❌ Infrastructure management      |
| **Flexibility**            | ⚠️ Limited customization<br>⚠️ AWS-specific features                                                                   | ✅ Full control over configuration<br>✅ Custom extensions possible                               |
| **Vendor Lock-in**         | ❌ AWS-specific service<br>❌ Migration complexity                                                                     | ✅ Portable across platforms<br>✅ Standard PostgreSQL                                            |
| **Learning Curve**         | ✅ Minimal database administration<br>✅ AWS console management                                                        | ❌ Kubernetes + PostgreSQL expertise<br>❌ Complex troubleshooting                                |

### ExternalName Service Pattern
An **ExternalName** service in Kubernetes allows you to create a service that points to an external resource, such as an AWS RDS instance. This is useful for integrating external databases or services into your Kubernetes applications without needing to manage the lifecycle of those resources within Kubernetes. This uses
**Benefits of ExternalName Service:**

- **Service Discovery**: Applications connect via standard Kubernetes DNS
- **Flexibility**: Easy to switch between different RDS endpoints
- **Abstraction**: Decouples application from specific database endpoints
- **Environment Consistency**: Same service name across dev/staging/prod



### Creating Kubernetes Secrets and configmaps with rds db details

Secrets are used to store sensitive information like database credentials, while ConfigMaps are used to store non-sensitive configuration data. We will create a Kubernetes Secret for the RDS database credentials and a ConfigMap for the application configuration. Configmaps use `key-value` pairs to store non-sensitive data as environment variables, while secrets use `base64` encoding to store sensitive data.

Youll need base64 encoding for the username, password, secret key and database url (enter one by one):

```bash
echo -n '<your-rds-username>' | base64
echo -n '<your-rds-password>' | base64
echo -n '<your-secret-key>' | base64
echo -n 'postgresql://postgresadmin:YourStrongPassword123!@postgres-db.3-tier-app-eks.svc.cluster.local:5432/postgres' | base64
```
change the `postgresadmin` and `YourStrongPassword123!` with your actual RDS username and password.

Now using the secret manifest edit the values with your base64 encoded values and apply the secret manifest:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rds-secret
  namespace: 3-tier-app-eks
type: Opaque
data:
  DB_USERNAME: <your-base64-encoded-username>
  DB_PASSWORD: <your-base64-encoded-password>
  DB_SECRET_KEY: ZGV2LXNlY3JldC1rZXk=
  DATABASE_URL: <your-base64-encoded-database-url>
```

Keep secret key the same as in the backend app it defaults to `dev-secret-key` but you can change it to whatever you want. its better to generate a random secret key for production use, but for now lets leave as is.

The database url is `postgresql://postgresadmin:YourStrongPassword123!@postgres-db.3-tier-app-eks.svc.cluster.local:5432/postgres` it encapsulates the username, password, host, port and database name. This is how the application will connect to the RDS database.


Apply the secret manifest:
```bash
kubectl apply -f secrets.yaml
```

Now we will create a ConfigMap for the application configuration. This will store non-sensitive data like the application host and port.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: 3-tier-app-eks
data:
  DB_HOST: "postgres-db.3-tier-app-eks.svc.cluster.local"
  DB_NAME: "postgres"
  DB_PORT: "5432"
  FLASK_DEBUG: "0"
```
Apply the config manifest:
```bash
kubectl apply -f configmap.yaml
```

![](/images/img-8.png)

***Running database migrations***

In this project theres a database migration that needs to be run before deploying the backend service. This is done using a Kubernetes Job, which is a one-time task that runs to completion, this will create database tables and seed data for the application to work correctly.

What a job does is it creates a pod that runs the specified command and then exits. If the command fails, the job will retry until it succeeds or reaches the specified backoff limit.

 This command `kubectl apply -f migration_job.yaml` will create a job that runs the command to apply the database migrations. This command will create the necessary tables and seed data in the RDS PostgreSQL database. Its worth analysing the job manifest to understand what it does and how it works. this is where the secrets and configmaps we created earlier will be used to connect to the database. its better than hardcoding the database credentials in the job manifest, because it allows you to change the credentials without modifying the job manifest.

```bash
#run these one by one
kubectl apply -f migration_job.yaml
kubectl get job -A
kubectl get pods -n 3-tier-app-eks
#get the name of the pod created by the job
kubectl logs <name-of-pod> -n 3-tier-app-eks
```

![](/images/img-9.png)

### Backend and Frontend services
Now lets deploy the backend and frontend services. The backend service is a Flask application that connects to the RDS PostgreSQL database, and the frontend service is a React application that communicates with the backend service.

Read the manifest files for the backend and frontend services to understand what they do and how they work. The backend service will use the secrets and configmaps we created earlier to connect to the database and configure the application.
The frontend service will use the backend service's URL to communicate with it.
```bash
#apply the backend service manifest
kubectl apply -f backend-service.yaml
#apply the frontend service manifest
kubectl apply -f frontend-service.yaml
#check the status of the pods
kubectl get deployment -n 3-tier-app-eks
kubectl get svc -n 3-tier-app-eks
```
![](/images/img-10.png)

### Accessing the application
At the minute we havent created ingress resources to expose the application to the internet. To access the application, we will port-forward the frontend service to our local machine. This will allow us to access the application using `localhost` and a specific port. Open two terminal windows, one for the backend service and one for the frontend service. In the first terminal window, run the following command to port-forward the backend service: We need to open new terminals because the port-forward command will block the terminal until you stop it with `CTRL+C`.

```bash
#port-forward the backend service to localhost:8000
kubectl port-forward svc/backend 8000:8000 -n 3-tier-app-eks
#port-forward the frontend service to localhost:8080
kubectl port-forward svc/frontend 8080:80 -n 3-tier-app-eks
```
![](/images/img-11.png)

you can access the backend service at `http://localhost:8000/api/topics` in the browser or `curl http://localhost:8000/api/topics` in the terminal.

![](/images/img-12.png)

you can access the frontend service at `http://localhost:8080` in the browser. The frontend service will communicate with the backend service to fetch data and display it.

![](/images/img-13.png)

this is a devops quiz application that you can use. the seed data created some samples, in the manage questions you can add more questions and answers. the `3-tier-app-eks/backend/questions-answers` includes some csv files that you can use to import questions and answers into the application. You can also add your own questions and answers using the frontend interface.

### Time to implement Ingress

An ingress is a Kubernetes resource that manages external access to services in a cluster, typically via HTTP/HTTPS. It provides load balancing, SSL termination and name-based virtual hosting.

The aws load balancer controller is a Kubernetes controller that manages AWS Elastic Load Balancers (ELBs) for Kubernetes services. It automatically provisions and configures ELBs based on the ingress resources defined in the cluster. This allows you to expose your services to the internet using a load balancer, without having to manually create and configure the ELB in AWS.

***Why Set Up an OIDC Provider for EKS?***\
OIDC has a "trust relationship" between your EKS cluster and AWS IAM. It tells AWS that your EKS cluster can issue tokens that AWS will trust for IAM role assumption.

Without OIDC:

    You'd have to put AWS access keys directly in your pods (insecure) or give every node excessive permissions.


With IRSA + OIDC:

    Each pod (via its service account) can assume an IAM role via a web identity token issued by Kubernetes.

    AWS trusts that OIDC token because you’ve registered your cluster's OIDC provider with IAM.

```bash
export cluster_name=Tawfiq-cluster
#this command will get the OIDC issuer ID for your EKS cluster
oidc_id=$(aws eks describe-cluster --name $cluster_name \
--query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

echo $oidc_id

# Check if IAM OIDC provider with your cluster's issuer ID
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4

# If not, create an OIDC provider
eksctl utils associate-iam-oidc-provider --cluster $cluster_name --approve

# or use console
# -> To create a provider, go to IAM, choose Add provider.
# -> For Provider type, select OpenID Connect.
# -> For Provider URL, enter the OIDC provider URL for your cluster.
# -> For Audience, enter sts.amazonaws.com.
# -> (Optional) Add any tags, for example a tag to identify which cluster is for this provider.
# -> Choose Add provider.
```

This creates the OIDC provider in IAM and associates it with your EKS cluster. This allows your cluster to issue tokens that AWS will trust for IAM role assumption.

### Create IAM Policy for AWS Load Balancer Controller
This command will create the IAM policy needed for the AWS Load Balancer Controller. The AWS Load Balancer Controller is allowed to create/modify/delete load balancers, target groups, security groups, etc.
```bash
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
```

Create service account in Kubernetes with the policy attached. this is where the IRSA (IAM Roles for Service Accounts) comes into play.\
This creates a bridge between Kubernetes and AWS:\
Kubernetes side: A service account that pods can use.\
AWS side: An IAM role with load balancer permissions\
Connection: The OIDC provider links them together

```bash
# Use the account id for your account
eksctl create iamserviceaccount \
  --cluster=$cluster_name \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::373317459404:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
#get your own arn from the json command above or check the AWS console in policies
# verify its creation
kubectl get serviceaccount -n kube-system | grep -i aws-load-balancer-controller
```

![](/images/img-14.png)


***Example Use Case | AWS Load Balancer Controller***

Let’s say your EKS cluster needs to automatically create and manage Application Load Balancers (ALBs) for your Kubernetes Ingress resources. With IRSA + OIDC:

    ✅ You create an IAM policy with permissions for managing load balancers (like ALBs, target groups, security groups).

    ✅ You attach that policy to an IAM role.

    ✅ You map that IAM role to a Kubernetes service account (e.g., aws-load-balancer-controller in kube-system).

    ✅ When the controller pod runs, it uses this service account, and AWS trusts the OIDC token from the pod to allow it to assume the IAM role.

    ✅ The controller can now securely call AWS APIs (like creating ALBs) without any static credentials or node-level IAM access.


### Installing the AWS Load Balancer Controller using Helm
What are CRDs?
Kubernetes comes with built-in resources like `Pod`, `Service`, `Deployment`. But it doesn't know about AWS-specific things like `TargetGroupBinding` or advanced `Ingress` features.

CRDs teach Kubernetes about these new resource types. These aren't built into Kubernetes.\
They're defined by AWS’s controller and only make sense in the AWS context.\
Kubernetes Itself Doesn't Know About AWS Load Balancers\
Kubernetes doesn’t natively know how to create AWS ALBs or NLBs. It only understands generic concepts like:`Service of type LoadBalancer` or `Ingress`\
But to translate those into actual AWS resources, you need something like:
`AWS Load Balancer Controller (for ALBs and NLBs)`
```bash
# this will install the CRDs needed for the controller
# CRDs are Custom Resource Definitions, they allow you to extend Kubernetes with your own resources, in this case, the AWS Load Balancer Controller uses CRDs to define resources like TargetGroupBinding, Ingress, etc.
kubectl apply -k  \
"github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master"

# install helm if haven't already
brew install helm # (for mac, google for other platforms)

# Add the EKS Helm chart repository. If you tried to install the AWS Load Balancer Controller manually, you'd need to apply dozens of YAML files in the correct order:
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# what this does is it installs the AWS Load Balancer Controller in the kube-system namespace, using the service account we created earlier. It also sets the cluster name, VPC ID and region for the controller to use.
# This allows the controller to manage load balancers in your cluster and automatically create them for your services.
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$cluster_name \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=$VPC_ID \
  --set region=eu-west-2
  ```

Helm takes your `--set` parameters and automatically generates all the YAML files with your custom values filled in.
Helm uses templates with placeholders that get filled with your values

Helm is the package manager for Kubernetes. Think of it like:
**apt** or **yum** for Linux, or **pip** for Python.\
But instead of installing OS packages or libraries, Helm installs Kubernetes applications (which are usually a big set of YAML files, configs, CRDs, etc).

Why Use Helm Here?

Doing this manually would be dozens of kubectl apply -f commands with templated YAML. Helm bundles all that up into a reusable chart.

The `eks/aws-load-balancer-controller` chart contains:
```plaintext
aws-load-balancer-controller/
├── Chart.yaml                    # Chart metadata
├── values.yaml                   # Default configuration
├── templates/
│   ├── deployment.yaml           # Controller pods
│   ├── serviceaccount.yaml       # (Optional - we skip this)
│   ├── clusterrole.yaml          # Kubernetes permissions
│   ├── clusterrolebinding.yaml   # Link SA to permissions
│   ├── configmap.yaml            # Configuration data
│   ├── service.yaml              # Internal service
│   └── webhooks.yaml             # Admission controllers
└── README.md                     # Installation docs
```

![](/images/img-15.png)


### Creating an Ingress class for alb and an Ingress resource to access the frontend service

Before creating the Ingress, you need to tag your public subnets so the AWS Load Balancer Controller knows where to deploy the ALB.\
Why this is needed: The AWS Load Balancer Controller uses specific tags to automatically discover which subnets to use for load balancers.\
You can do this in the AWS console or using the AWS CLI.

List the public subnet for the EKS cluster, and apply the tag
```bash
# reuse the VPC ID for the EKS cluster
# Public subnets for the cluster
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
--query "Subnets[*].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,PublicIp:MapPublicIpOnLaunch}"

# Get the list of subnets id's from above commands and run this
# Update the correct subnet id's
aws ec2 create-tags --resources subnet-765gf45367hjd4563 subnet-765gfd45631643 \
subnet-765gf45367hjd4563 --tags Key=kubernetes.io/role/elb,Value=1

# Verify the tags
aws ec2 describe-subnets --subnet-ids subnet-765gf45367hjd4563 subnet-765gfd45631643 \
subnet-765gf45367hjd4563 --query "Subnets[*].{SubnetId:SubnetId,Tags:Tags}"
```
![](/images/img-16.png)

Now apply the ingress manifest using `kubectl apply -f ingress.yaml`. To create the ingress class and ingress resource. The ingress class is used to specify which ingress controller to use for the ingress resource. In this case, we are using the AWS Load Balancer Controller as the ingress controller.

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "false"
spec:
  controller: ingress.k8s.aws/alb
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: 3-tier-app-ingress
  namespace: 3-tier-app-eks
  annotations:
    alb.ingress.kubernetes.io/scheme: "internet-facing"
    alb.ingress.kubernetes.io/target-type: "ip"
    alb.ingress.kubernetes.io/healthcheck-path: "/"  # healthcheck path
spec:
  ingressClassName: "alb"
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend
            port:
              number: 8000
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
```
```bash
# Check the ingress and load balancer controller logs
kubectl get ingress -n 3-tier-app-eks
kubectl describe ingress 3-tier-app-ingress -n 3-tier-app-eks

# After ingress creation
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```


![](/images/img-17.png)


It may take a few minutes for the ALB to be provisioned and the DNS name to be available. Once it is available, you can access the application using the DNS name of the ALB in aws by searching loadbalancer, click the loadbalancer created and copy the DNS and paste it in the browser.

![](/images/img-18.png)



### Whats Next and how can we improve?
In this project, we have successfully deployed a three-tier application on AWS EKS using Kubernetes. We have used Docker to containerize the application, Kubernetes to orchestrate the deployment, and AWS services like RDS for the database and ALB for load balancing.
The next future steps will be to implement monitoring and logging for the application using tools like Prometheus, Grafana. This will help us monitor the application's performance and troubleshoot any issues that may arise.

Another future step will be to implement CI/CD for the application using GitHub Actions. This will allow us to automate the deployment process and ensure that the application is always up-to-date with the latest changes.

We can also use route53 to create a custom domain for the application and point it to the ALB. This will allow us to access the application using a custom domain name instead of the ALB DNS name.


### To delete the cluster and all resources created
To delete the RDS instance, you can use the following command:
```bash
#can take a while to delete
aws rds delete-db-instance \
--db-instance-identifier tawfiq-db \
--skip-final-snapshot \
--region eu-west-2

aws rds delete-db-subnet-group \
  --db-subnet-group-name tawfiq-db-subnet-group \
  --region eu-west-2
```

To delete the EKS cluster and all resources created, you can use the following command:
```bash
eksctl delete cluster Tawfiq-cluster --region eu-west-2
```
This will delete the EKS cluster, the VPC, the RDS instance, and all other resources created during the setup. Make sure to back up any data you want to keep before running this command, as it will permanently delete all resources associated with the cluster.

Double check the AWS console to ensure all resources are deleted, as sometimes some resources may not be deleted automatically due to dependencies or other issues.
