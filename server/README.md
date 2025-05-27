# DOCX Merger Service

A Flask-based service for merging multiple DOCX files into a single document.

## Setup

1. Create a virtual environment (recommended):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

## Running the Service

Start the server:
```bash
python app.py
```

The service will run on `http://localhost:5000`

## API Endpoints

### Health Check
- **GET** `/health`
- Returns service status and timestamp

### Merge Documents
- **POST** `/merge`
- Accepts multiple DOCX files
- Returns merged DOCX file

### Example Usage with curl:
```bash
curl -X POST -F "files=@file1.docx" -F "files=@file2.docx" http://localhost:5000/merge --output merged.docx
```

## Features

- Merges multiple DOCX files into a single document
- Preserves formatting and styles
- Adds page breaks between documents
- Generates timestamped filenames
- CORS enabled for web applications
- Error handling and validation 