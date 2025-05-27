from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
from docx import Document
import io
import os
from datetime import datetime
from docxcompose.composer import Composer

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/merge', methods=['POST'])
def merge_docs():
    try:
        files = request.files.getlist('files')
        if not files:
            return jsonify({"error": "No files provided"}), 400

        # Use the first file as the base document
        base_doc = Document(files[0])
        composer = Composer(base_doc)

        # Append the rest
        for file in files[1:]:
            doc = Document(file)
            composer.append(doc)

        output = io.BytesIO()
        composer.save(output)
        output.seek(0)

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'merged_document_{timestamp}.docx'

        return send_file(
            output,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=True) 