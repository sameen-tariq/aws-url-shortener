FROM python:3.12-slim
WORKDIR /app
RUN pip install boto3 flask
COPY . .
RUN echo "from flask import Flask, jsonify\nimport boto3, os\napp = Flask(__name__)\n@app.route('/health')\ndef health(): return jsonify({'status': 'ok'})\nif __name__ == '__main__': app.run(host='0.0.0.0', port=80)" > app.py
EXPOSE 80
CMD ["python", "app.py"]
