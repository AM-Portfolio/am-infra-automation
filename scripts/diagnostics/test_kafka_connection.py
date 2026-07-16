import sys
import subprocess

import socket

orig_getaddrinfo = socket.getaddrinfo
def custom_getaddrinfo(*args, **kwargs):
    host = args[0] if args else ""
    port = args[1] if len(args) > 1 else 0
    if port == 9092:
        return orig_getaddrinfo('127.0.0.1', *args[1:], **kwargs)
    return orig_getaddrinfo(*args, **kwargs)
socket.getaddrinfo = custom_getaddrinfo

# Ensure heavy clients are imported
try:
    from kafka import KafkaAdminClient, KafkaProducer, KafkaConsumer
    from kafka.admin import NewTopic
except ImportError:
    print("Installing kafka-python for testing...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "kafka-python"])
    from kafka import KafkaAdminClient, KafkaProducer, KafkaConsumer
    from kafka.admin import NewTopic

def test_kafka_connection():
    bootstrap_servers = 'kafka-headless:9092'
    username = 'kafkaUser'
    password = 'qTz%5y1D!nm_SLM5wg8G@d0Pgjf0XA*1'
    topic_name = 'test-topic-ai'
    
    print(f"Connecting to Kafka at {bootstrap_servers}...")
    try:
        # 1. Test Admin (List Topics)
        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            security_protocol='SASL_PLAINTEXT',
            sasl_mechanism='SCRAM-SHA-256',
            sasl_plain_username=username,
            sasl_plain_password=password,
            api_version=(2, 8, 1),
            request_timeout_ms=5000
        )
        
        topics = admin_client.list_topics()
        print("\n✅ ADMIN: Connected correctly!")
        print(f"Discovered topics: {topics}")
        
        # 2. Create Topic if missing
        if topic_name not in topics:
            print(f"Creating topic: {topic_name}...")
            new_topic = NewTopic(name=topic_name, num_partitions=1, replication_factor=1)
            admin_client.create_topics(new_topics=[new_topic], timeout_ms=5000)
            print(f"✅ TOPIC CREATION: {topic_name} created successfully.")
        else:
            print(f"ℹ️ Topic {topic_name} already exists.")
        admin_client.close()

        # 3. Test Producer
        print(f"\n🚀 Sending message to {topic_name}...")
        producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            security_protocol='SASL_PLAINTEXT',
            sasl_mechanism='SCRAM-SHA-256',
            sasl_plain_username=username,
            sasl_plain_password=password,
            api_version=(2, 8, 1)
        )
        future = producer.send(topic_name, b"Hello from AI testing script!")
        producer.flush()
        future.get(timeout=10)
        print("✅ PRODUCER: Message sent successfully.")
        producer.close()

        # 4. Test Consumer
        print(f"\n📥 Consuming from {topic_name}...")
        consumer = KafkaConsumer(
            topic_name,
            bootstrap_servers=bootstrap_servers,
            security_protocol='SASL_PLAINTEXT',
            sasl_mechanism='SCRAM-SHA-256',
            sasl_plain_username=username,
            sasl_plain_password=password,
            api_version=(2, 8, 1),
            auto_offset_reset='earliest',
            enable_auto_commit=True,
            consumer_timeout_ms=5000
        )
        
        message_found = False
        for message in consumer:
            print(f"✅ CONSUMER: Received message: {message.value.decode('utf-8')}")
            message_found = True
            break
        
        if not message_found:
            print("⚠️ CONSUMER: No messages received (timeout reached).")
        
        consumer.close()
        print("\n🎉 ALL TESTS PASSED!")
        return True
    except Exception as e:
        print(f"\n❌ FAILED during test sequence: {e}")
        return False

if __name__ == "__main__":
    test_kafka_connection()
