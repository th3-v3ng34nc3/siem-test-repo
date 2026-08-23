import os
import json
import gzip
import base64
import urllib.request
import ssl

def get_env_config():
    return {
        "target_url": os.environ.get("TARGET_URL"),
        "chunk_size": int(os.environ.get("CHUNK_SIZE_LIMIT", 3 * 1024 * 1024)),
        "line_limit": int(os.environ.get("LINE_LIMIT", 1000)),
        "user": os.environ.get("BASIC_USER"),
        "password": os.environ.get("BASIC_PASS"),
        "insecure_tls": os.environ.get("INSECURE_TLS_SKIP", "false").lower() == "true"
    }

def lambda_handler(event, context):
    config = get_env_config()
    
    # CloudWatch logs are base64 encoded and gzipped
    compressed_payload = base64.b64decode(event['awslogs']['data'])
    uncompressed_payload = gzip.decompress(compressed_payload)
    log_data = json.loads(uncompressed_payload)
    
    log_events = log_data['logEvents']
    chunk = []
    current_size = 0

    for i, entry in enumerate(log_events):
        msg_str = json.dumps(entry) + "\n"
        msg_bytes = msg_str.encode('utf-8')
        
        # Check limits
        if (current_size + len(msg_bytes) > config['chunk_size']) or (len(chunk) >= config['line_limit']):
            send_to_endpoint(chunk, config)
            chunk = []
            current_size = 0
            
        chunk.append(entry)
        current_size += len(msg_bytes)

    if chunk:
        send_to_endpoint(chunk, config)

def send_to_endpoint(batch, config):
    data = json.dumps(batch).encode('utf-8')
    req = urllib.request.Request(config['target_url'], data=data, method='POST')
    req.add_header('Content-Type', 'application/json')
    
    if config['user'] and config['password']:
        auth = base64.b64encode(f"{config['user']}:{config['password']}".encode()).decode()
        req.add_header('Authorization', f'Basic {auth}')

    ctx = ssl.create_default_context()
    if config['insecure_tls']:
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    with urllib.request.urlopen(req, context=ctx) as f:
        return f.status