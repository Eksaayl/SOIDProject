from fastapi import FastAPI, UploadFile, File, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse, FileResponse
from docx import Document
from docxcompose.composer import Composer
import io
import os
from typing import List
from datetime import datetime
import uvicorn
from docx.shared import Inches
import tempfile
import uuid
from server.tables import create_iii_b_docx, create_iii_a_docx
import argparse
import mammoth

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def append_docx_with_section_break(master, doc_to_append):
    while master.paragraphs and not master.paragraphs[-1].text.strip():
        p = master.paragraphs[-1]._element
        p.getparent().remove(p)

    from docx.oxml import OxmlElement
    from docx.oxml.ns import qn

    p = master.paragraphs[-1]._element
    pPr = p.get_or_add_pPr()
    sectPr = OxmlElement('w:sectPr')
    type_ = OxmlElement('w:type')
    type_.set(qn('w:val'), 'nextPage')
    sectPr.append(type_)
    pPr.append(sectPr)

    if hasattr(doc_to_append, 'part'):
        if hasattr(doc_to_append.part, 'styles_part'):
            if not hasattr(master.part, 'styles_part'):
                master.part.styles_part = doc_to_append.part.styles_part
            else:
                for style in doc_to_append.part.styles_part.element:
                    existing_style = master.part.styles_part.element.find(
                        f'.//w:style[@w:styleId="{style.get(qn("w:styleId"))}"]',
                        {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
                    )
                    if existing_style is None:
                        master.part.styles_part.element.append(style)

        if hasattr(doc_to_append.part, 'numbering_part'):
            if not hasattr(master.part, 'numbering_part'):
                master.part.numbering_part = doc_to_append.part.numbering_part
            else:
                for num in doc_to_append.part.numbering_part.element:
                    master.part.numbering_part.element.append(num)

    for element in doc_to_append.element.body:
        master.element.body.append(element)

    for paragraph in master.paragraphs:
        if hasattr(paragraph, '_element'):
            p = paragraph._element
            if hasattr(paragraph, 'style') and paragraph.style:
                pPr = p.get_or_add_pPr()
                pStyle = OxmlElement('w:pStyle')
                pStyle.set(qn('w:val'), paragraph.style.name)
                pPr.append(pStyle)

async def generate_docx_II_a(template_file, images):
    try:
        doc = Document(template_file)
        sorted_images = sorted(images, key=lambda x: x.filename)
        image_map = {
            'ISI': None,
            'ISII': None,
            'ISIII': None,
        }
        
        for i, img in enumerate(sorted_images):
            if i == 0:
                image_map['ISI'] = img
            elif i == 1:
                image_map['ISII'] = img
            elif i == 2:
                image_map['ISIII'] = img
        
        for paragraph in doc.paragraphs:
            if '{ISI}' in paragraph.text:
                if image_map['ISI']:
                    img_content = await image_map['ISI'].read()
                    img_stream = io.BytesIO(img_content)
                    paragraph.clear()
                    run = paragraph.add_run()
                    run.add_picture(img_stream, width=Inches(6))
            elif '{ISII}' in paragraph.text:
                if image_map['ISII']:
                    img_content = await image_map['ISII'].read()
                    img_stream = io.BytesIO(img_content)
                    paragraph.clear()
                    run = paragraph.add_run()
                    run.add_picture(img_stream, width=Inches(6))
            elif '{ISIII}' in paragraph.text:
                if image_map['ISIII']:
                    img_content = await image_map['ISIII'].read()
                    img_stream = io.BytesIO(img_content)
                    paragraph.clear()
                    run = paragraph.add_run()
                    run.add_picture(img_stream, width=Inches(6))
        
        docx_bytes = io.BytesIO()
        doc.save(docx_bytes)
        docx_bytes.seek(0)
        
        return docx_bytes.getvalue()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate Part II.A document: {str(e)}")

async def generate_docx_II_d(template_file, images):
    try:
        doc = Document(template_file)
        sorted_images = sorted(images, key=lambda x: x.filename)
        image_map = {
            'NLC': None,
            'PNL': None,
        }
        
        for i, img in enumerate(sorted_images):
            if i == 0:
                image_map['NLC'] = img
            elif i == 1:
                image_map['PNL'] = img
        
        for paragraph in doc.paragraphs:
            if '{NLC}' in paragraph.text:
                if image_map['NLC']:
                    img_content = await image_map['NLC'].read()
                    img_stream = io.BytesIO(img_content)
                    paragraph.clear()
                    run = paragraph.add_run()
                    run.add_picture(img_stream, width=Inches(6))
            elif '{PNL}' in paragraph.text:
                if image_map['PNL']:
                    img_content = await image_map['PNL'].read()
                    img_stream = io.BytesIO(img_content)
                    paragraph.clear()
                    run = paragraph.add_run()
                    run.add_picture(img_stream, width=Inches(6))
        
        docx_bytes = io.BytesIO()
        doc.save(docx_bytes)
        docx_bytes.seek(0)
        
        return docx_bytes.getvalue()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate Part II.D document: {str(e)}")

@app.post("/generate-docx")
async def generate_docx(
    template: UploadFile = File(...),
    images: List[UploadFile] = File(...),
):
    template_file = None
    try:
        if not template.filename:
            raise HTTPException(status_code=400, detail="Template filename is required")
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        template_file = f"temp_template_{timestamp}.docx"
        
        try:
            with open(template_file, "wb") as f:
                f.write(await template.read())
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to save template file: {str(e)}")
        
        if not images:
            raise HTTPException(status_code=400, detail="At least one image is required")
        
        try:
            if "templates_II_a.docx" in template.filename:
                if len(images) != 3:
                    raise HTTPException(status_code=400, detail="Part II.A requires exactly 3 images")
                docx_bytes = await generate_docx_II_a(template_file, images)
            elif "templates_II_d.docx" in template.filename:
                if len(images) != 2:
                    raise HTTPException(status_code=400, detail="Part II.D requires exactly 2 images")
                docx_bytes = await generate_docx_II_d(template_file, images)
            else:
                raise HTTPException(status_code=400, detail=f"Invalid template file: {template.filename}")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to generate document: {str(e)}")
        
        return StreamingResponse(
            io.BytesIO(docx_bytes),
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")
    finally:
        if template_file and os.path.exists(template_file):
            try:
                os.remove(template_file)
            except Exception as e:
                print(f"Warning: Failed to remove temporary file {template_file}: {str(e)}")

@app.post("/merge-documents-part-i-all")
async def merge_documents_part_i_all(
    part_ia: UploadFile = File(...),
    part_ib: UploadFile = File(...),
    part_ic: UploadFile = File(...),
    part_id: UploadFile = File(...),
    part_ie: UploadFile = File(...),
):
    try:
        try:
            ia_bytes = io.BytesIO(await part_ia.read())
            ib_bytes = io.BytesIO(await part_ib.read())
            ic_bytes = io.BytesIO(await part_ic.read())
            id_bytes = io.BytesIO(await part_id.read())
            ie_bytes = io.BytesIO(await part_ie.read())
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to read uploaded files: {str(e)}")

        try:
            ia_doc = Document(ia_bytes)
            ib_doc = Document(ib_bytes)
            ic_doc = Document(ic_bytes)
            id_doc = Document(id_bytes)
            ie_doc = Document(ie_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to parse DOCX files: {str(e)}")

        def add_page_break(doc):
            try:
                p = doc.add_paragraph()
                run = p.add_run()
                run.add_break()
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Failed to add page break: {str(e)}")

        try:
            add_page_break(ia_doc)
            add_page_break(ib_doc)
            add_page_break(ic_doc)
            add_page_break(id_doc)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to add page breaks: {str(e)}")

        try:
            composer = Composer(ia_doc)
            composer.append(ib_doc)
            composer.append(ic_doc)
            composer.append(id_doc)
            composer.append(ie_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to merge documents: {str(e)}")

        try:
            output = io.BytesIO()
            composer.save(output)
            output.seek(0)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to save merged document: {str(e)}")

        return StreamingResponse(
            output,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Unexpected error in merge_documents_part_i_all: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")

@app.post("/merge-documents-part-ii")
async def merge_documents_part_ii(
    part_ii_a: UploadFile = File(...),
    part_ii_b: UploadFile = File(...),
    part_ii_c: UploadFile = File(...),
    part_ii_d: UploadFile = File(...),
):
    try:
        try:
            ii_a_bytes = io.BytesIO(await part_ii_a.read())
            ii_b_bytes = io.BytesIO(await part_ii_b.read())
            ii_c_bytes = io.BytesIO(await part_ii_c.read())
            ii_d_bytes = io.BytesIO(await part_ii_d.read())
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to read uploaded files: {str(e)}")

        try:
            ii_a_doc = Document(ii_a_bytes)
            ii_b_doc = Document(ii_b_bytes)
            ii_c_doc = Document(ii_c_bytes)
            ii_d_doc = Document(ii_d_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to parse DOCX files: {str(e)}")

        def add_page_break(doc):
            try:
                p = doc.add_paragraph()
                run = p.add_run()
                run.add_break()
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Failed to add page break: {str(e)}")

        try:
            add_page_break(ii_a_doc)
            add_page_break(ii_b_doc)
            add_page_break(ii_c_doc)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to add page breaks: {str(e)}")

        try:
            composer = Composer(ii_a_doc)
            composer.append(ii_b_doc)
            composer.append(ii_c_doc)
            composer.append(ii_d_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to merge documents: {str(e)}")
        
        try:
            output = io.BytesIO()
            composer.save(output)
            output.seek(0)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to save merged document: {str(e)}")

        return StreamingResponse(
            output,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Unexpected error in merge_documents_part_ii: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")

@app.post("/merge-documents-part-iii")
async def merge_documents_part_iii(
    part_iii_a: UploadFile = File(...),
    part_iii_b: UploadFile = File(...),
    part_iii_c: UploadFile = File(...),
):
    try:
        # Read uploaded files
        try:
            iii_a_bytes = io.BytesIO(await part_iii_a.read())
            iii_b_bytes = io.BytesIO(await part_iii_b.read())
            iii_c_bytes = io.BytesIO(await part_iii_c.read())
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to read uploaded files: {str(e)}")

        # Parse DOCX files
        try:
            iii_a_doc = Document(iii_a_bytes)
            iii_b_doc = Document(iii_b_bytes)
            iii_c_doc = Document(iii_c_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to parse DOCX files: {str(e)}")

        # Optionally add page breaks between docs
        def add_page_break(doc):
            try:
                p = doc.add_paragraph()
                run = p.add_run()
                run.add_break()
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Failed to add page break: {str(e)}")

        try:
            add_page_break(iii_a_doc)
            add_page_break(iii_b_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to add page breaks: {str(e)}")

        # Merge documents
        try:
            composer = Composer(iii_a_doc)
            composer.append(iii_b_doc)
            composer.append(iii_c_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to merge documents: {str(e)}")

        # Save merged document to bytes
        try:
            output = io.BytesIO()
            composer.save(output)
            output.seek(0)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to save merged document: {str(e)}")

        return StreamingResponse(
            output,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except HTTPException:
        raise
    except Exception as e:
        print(f"Unexpected error in merge_documents_part_iii: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")

@app.post("/generate-iii-b-docx/")
async def generate_iii_b_docx_endpoint(request: Request):
    projects = await request.json()
    temp_dir = tempfile.gettempdir()
    filename = f"iii_b_{uuid.uuid4().hex}.docx"
    output_path = os.path.join(temp_dir, filename)
    create_iii_b_docx(projects, output_path)
    return FileResponse(output_path, filename="document.docx", media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document")

@app.post("/generate-iii-a-docx/")
async def generate_iii_a_docx_endpoint(request: Request):
    projects = await request.json()
    temp_dir = tempfile.gettempdir()
    filename = f"iii_a_{uuid.uuid4().hex}.docx"
    output_path = os.path.join(temp_dir, filename)
    create_iii_a_docx(projects, output_path)
    return FileResponse(output_path, filename="document.docx", media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document")

@app.post("/convert-docx")
async def convert_docx(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No selected file")
    try:
        contents = await file.read()
        with open("temp_upload.docx", "wb") as f:
            f.write(contents)
        with open("temp_upload.docx", "rb") as docx_file:
            result = mammoth.convert_to_html(docx_file)
            html = result.value
        os.remove("temp_upload.docx")
        return {"html": html}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to convert DOCX: {str(e)}")

@app.get("/")
async def root():
    return {"message": "Document Merge Server is running"}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000, help="Port to run the server on")
    args = parser.parse_args()
    uvicorn.run(app, host="0.0.0.0", port=args.port) 