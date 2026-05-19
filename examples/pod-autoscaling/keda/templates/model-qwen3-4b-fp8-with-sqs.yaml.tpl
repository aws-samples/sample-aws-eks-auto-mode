apiVersion: apps/v1
kind: Deployment
metadata:
  name: model-qwen3-4b-fp8
  namespace: vllm
spec:
  replicas: 0  # KEDA will manage scaling from 0
  selector:
    matchLabels:
      app: model-qwen3-4b-fp8
  template:
    metadata:
      labels:
        app: model-qwen3-4b-fp8
    spec:
      serviceAccountName: sqs-reader-sa
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      nodeSelector:
        eks.amazonaws.com/instance-family: g6e
      containers:
        # Main vLLM container
        - name: vllm
          image: vllm/vllm-openai@sha256:0b51ec38fb965b44f6aa75d8d847c5f21bc062b7140e1d83444b39b67fc4a2ea
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - NET_RAW
            seccompProfile:
              type: RuntimeDefault
          command: ["vllm", "serve"]
          args:
            - Qwen/Qwen3-4B-FP8
            - --served-model-name=qwen3-4b-fp8
            - --trust-remote-code
            - --gpu-memory-utilization=0.95
            - --max-model-len=32768
            - --disable-log-requests
            - --enable-auto-tool-choice
            - --tool-call-parser=hermes
            - --reasoning-parser=qwen3
          ports:
            - name: http
              containerPort: 8000
          resources:
            requests:
              cpu: 3.5
              memory: 29Gi
              nvidia.com/gpu: 1
            limits:
              cpu: 3.5
              memory: 29Gi
              nvidia.com/gpu: 1

        
        # SQS Consumer sidecar
        - name: sqs-consumer
          image: python:3.9-slim
          command: ["/bin/bash"]
          args:
            - -c
            - |
              pip install boto3 requests
              python /app/sqs-consumer.py
          env:
            - name: SQS_QUEUE_URL
              value: "${sqs_queue_url}"
            - name: AWS_REGION
              value: "${aws_region}"
            - name: VLLM_ENDPOINT
              value: "http://localhost:8000"
          volumeMounts:
            - name: consumer-script
              mountPath: /app
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "500m"
      
      volumes:
        - name: consumer-script
          configMap:
            name: sqs-consumer-script
            defaultMode: 0755
      
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
---
apiVersion: v1
kind: Service
metadata:
  name: model-qwen3-4b-fp8
  namespace: vllm
spec:
  selector:
    app: model-qwen3-4b-fp8
  ports:
    - name: http
      port: 8000
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: sqs-consumer-script
  namespace: vllm
data:
  sqs-consumer.py: |
    #!/usr/bin/env python3
    import boto3
    import json
    import requests
    import time
    import os
    import logging
    from datetime import datetime

    # Configure logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logger = logging.getLogger(__name__)

    class SQSConsumer:
        def __init__(self, queue_url, aws_region, vllm_endpoint):
            self.queue_url = queue_url
            self.aws_region = aws_region
            self.vllm_endpoint = vllm_endpoint
            self.sqs_client = boto3.client('sqs', region_name=aws_region)
            
        def process_message(self, message_body):
            """Process a single message by sending it to vLLM"""
            try:
                # Parse the message
                data = json.loads(message_body)
                prompt = data.get('prompt', '')
                parameters = data.get('parameters', {})
                message_id = data.get('id', 'unknown')
                
                logger.info(f"Processing message {message_id}: {prompt[:50]}...")
                
                # Prepare vLLM request
                vllm_request = {
                    "model": "qwen3-4b-fp8",
                    "messages": [
                        {"role": "user", "content": prompt}
                    ],
                    "max_tokens": parameters.get('max_tokens', 150),
                    "temperature": parameters.get('temperature', 0.7),
                    "stream": False
                }
                
                # Send request to vLLM
                response = requests.post(
                    f"{self.vllm_endpoint}/v1/chat/completions",
                    json=vllm_request,
                    timeout=30
                )
                
                if response.status_code == 200:
                    result = response.json()
                    generated_text = result['choices'][0]['message']['content']
                    logger.info(f"✓ Successfully processed message {message_id}")
                    logger.info(f"Generated text: {generated_text[:100]}...")
                    return True
                else:
                    logger.error(f"✗ vLLM request failed for message {message_id}: {response.status_code}")
                    return False
                    
            except Exception as e:
                logger.error(f"✗ Error processing message: {e}")
                return False
        
        def poll_and_process(self):
            """Poll SQS queue and process messages"""
            logger.info(f"Starting SQS consumer...")
            logger.info(f"Queue URL: {self.queue_url}")
            logger.info(f"vLLM Endpoint: {self.vllm_endpoint}")
            logger.info(f"AWS Region: {self.aws_region}")
            logger.info("-" * 50)
            
            while True:
                try:
                    # Poll for messages
                    response = self.sqs_client.receive_message(
                        QueueUrl=self.queue_url,
                        MaxNumberOfMessages=1,
                        WaitTimeSeconds=20,  # Long polling
                        MessageAttributeNames=['All']
                    )
                    
                    messages = response.get('Messages', [])
                    
                    if not messages:
                        logger.info("No messages received, continuing to poll...")
                        continue
                    
                    for message in messages:
                        message_body = message['Body']
                        receipt_handle = message['ReceiptHandle']
                        
                        # Process the message
                        success = self.process_message(message_body)
                        
                        if success:
                            # Delete the message from queue
                            self.sqs_client.delete_message(
                                QueueUrl=self.queue_url,
                                ReceiptHandle=receipt_handle
                            )
                            logger.info("✓ Message deleted from queue")
                        else:
                            logger.warning("✗ Message processing failed, leaving in queue")
                    
                except Exception as e:
                    logger.error(f"Error in polling loop: {e}")
                    time.sleep(5)  # Wait before retrying

    def wait_for_vllm_ready(vllm_endpoint, max_retries=30, retry_delay=10):
        """Wait for vLLM to be ready"""
        logger.info(f"Waiting for vLLM to be ready at {vllm_endpoint}...")
        
        for attempt in range(max_retries):
            try:
                response = requests.get(f"{vllm_endpoint}/health", timeout=5)
                if response.status_code == 200:
                    logger.info("✓ vLLM is ready!")
                    return True
            except Exception as e:
                logger.info(f"Attempt {attempt + 1}/{max_retries}: vLLM not ready yet ({e})")
            
            time.sleep(retry_delay)
        
        logger.error("✗ vLLM failed to become ready within timeout")
        return False

    def main():
        # Get configuration from environment variables
        queue_url = os.getenv('SQS_QUEUE_URL')
        aws_region = os.getenv('AWS_REGION', 'us-west-2')
        vllm_endpoint = os.getenv('VLLM_ENDPOINT', 'http://localhost:8000')
        
        if not queue_url:
            logger.error("Error: SQS_QUEUE_URL environment variable is required")
            return
        
        # Wait for vLLM to be ready
        if not wait_for_vllm_ready(vllm_endpoint):
            logger.error("Exiting due to vLLM not being ready")
            return
        
        # Start the consumer
        consumer = SQSConsumer(queue_url, aws_region, vllm_endpoint)
        consumer.poll_and_process()

    if __name__ == "__main__":
        main()
