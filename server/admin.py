from flask import Blueprint, request, jsonify
import mammoth

admin_bp = Blueprint('admin', __name__)

@admin_bp.route('/convert-docx', methods=['POST'])
def convert_docx():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    try:
        result = mammoth.convert_to_html(file)
        html = result.value  
        return jsonify({'html': html})
    except Exception as e:
        return jsonify({'error': str(e)}), 500 