from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from docx import Document
from docxcompose.composer import Composer
import io
import os
from typing import List
import json
from pydantic import BaseModel
from datetime import datetime
import uvicorn
from docx.shared import Inches
import base64

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

@app.post("/merge-documents")
async def merge_documents(
    compiled: UploadFile = File(...),
    part_id: UploadFile = File(...),
    part_ie: UploadFile = File(...),
):
    try:
        compiled_bytes = io.BytesIO(await compiled.read())
        id_bytes = io.BytesIO(await part_id.read())
        ie_bytes = io.BytesIO(await part_ie.read())

        compiled_doc = Document(compiled_bytes)
        id_doc = Document(id_bytes)
        ie_doc = Document(ie_bytes)

        def add_page_break(doc):
            p = doc.add_paragraph()
            run = p.add_run()
            run.add_break()  

        add_page_break(compiled_doc)
        add_page_break(id_doc)

        composer = Composer(compiled_doc)
        composer.append(id_doc)
        composer.append(ie_doc)

        output = io.BytesIO()
        composer.save(output)
        output.seek(0)
        return StreamingResponse(
            output,
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/merge-documents-part-ii")
async def merge_documents_part_ii(
    part_ii_a: UploadFile = File(...),
    part_ii_b: UploadFile = File(...),
    part_ii_c: UploadFile = File(...),
    part_ii_d: UploadFile = File(...),
):
    try:
        # Read all documents
        try:
            ii_a_bytes = io.BytesIO(await part_ii_a.read())
            ii_b_bytes = io.BytesIO(await part_ii_b.read())
            ii_c_bytes = io.BytesIO(await part_ii_c.read())
            ii_d_bytes = io.BytesIO(await part_ii_d.read())
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to read uploaded files: {str(e)}")

        # Create Document objects
        try:
            ii_a_doc = Document(ii_a_bytes)
            ii_b_doc = Document(ii_b_bytes)
            ii_c_doc = Document(ii_c_bytes)
            ii_d_doc = Document(ii_d_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to parse DOCX files: {str(e)}")

        # Add page breaks between sections
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

        # Merge documents
        try:
            composer = Composer(ii_a_doc)
            composer.append(ii_b_doc)
            composer.append(ii_c_doc)
            composer.append(ii_d_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to merge documents: {str(e)}")

        # Save to bytes
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

@app.post("/merge-documents-part-i")
async def merge_documents_part_i(
    compiled: UploadFile = File(...),
    part_id: UploadFile = File(...),
    part_ie: UploadFile = File(...),
):
    try:
        # Read all documents
        try:
            compiled_bytes = io.BytesIO(await compiled.read())
            id_bytes = io.BytesIO(await part_id.read())
            ie_bytes = io.BytesIO(await part_ie.read())
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to read uploaded files: {str(e)}")

        # Create Document objects
        try:
            compiled_doc = Document(compiled_bytes)
            id_doc = Document(id_bytes)
            ie_doc = Document(ie_bytes)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Failed to parse DOCX files: {str(e)}")

        # Add page breaks between sections
        def add_page_break(doc):
            try:
                p = doc.add_paragraph()
                run = p.add_run()
                run.add_break()
            except Exception as e:
                raise HTTPException(status_code=500, detail=f"Failed to add page break: {str(e)}")

        try:
            add_page_break(compiled_doc)
            add_page_break(id_doc)
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to add page breaks: {str(e)}")

        # Merge documents
        try:
            composer = Composer(compiled_doc)
            composer.append(id_doc)
            composer.append(ie_doc)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to merge documents: {str(e)}")

        # Save to bytes
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
        print(f"Unexpected error in merge_documents_part_i: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")

@app.get("/")
async def root():
    return {"message": "Document Merge Server is running"}

class DocumentData(BaseModel):
    documentId: str
    sectionId: str
    data: dict

@app.post("/save-document")
async def save_document(data: DocumentData):
    try:
        # Create directory if it doesn't exist
        os.makedirs("documents", exist_ok=True)
        
        # Generate filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"documents/{data.documentId}_{data.sectionId}_{timestamp}.json"
        
        # Save data to file
        with open(filename, "w") as f:
            json.dump(data.data, f, indent=2)
        
        return {"status": "success", "filename": filename}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

async def generate_docx_II_a(template_file, images):
    try:
        # Create a copy of the template
        doc = Document(template_file)
        
        # Sort images by filename to ensure correct order
        sorted_images = sorted(images, key=lambda x: x.filename)
        
        # Map images to their corresponding placeholders
        image_map = {
            'ISI': None,
            'ISII': None,
            'ISIII': None,
        }
        
        # Map images based on their order
        for i, img in enumerate(sorted_images):
            if i == 0:
                image_map['ISI'] = img
            elif i == 1:
                image_map['ISII'] = img
            elif i == 2:
                image_map['ISIII'] = img
        
        # Add images to document
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
        
        # Save to bytes
        docx_bytes = io.BytesIO()
        doc.save(docx_bytes)
        docx_bytes.seek(0)
        
        return docx_bytes.getvalue()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate Part II.A document: {str(e)}")

async def generate_docx_II_d(template_file, images):
    try:
        # Create a copy of the template
        doc = Document(template_file)
        
        # Sort images by filename to ensure correct order
        sorted_images = sorted(images, key=lambda x: x.filename)
        
        # Map images to their corresponding placeholders
        image_map = {
            'NLC': None,
            'PNL': None,
        }
        
        # Map images based on their order
        for i, img in enumerate(sorted_images):
            if i == 0:
                image_map['NLC'] = img
            elif i == 1:
                image_map['PNL'] = img
        
        # Add images to document
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
        
        # Save to bytes
        docx_bytes = io.BytesIO()
        doc.save(docx_bytes)
        docx_bytes.seek(0)
        
        return docx_bytes.getvalue()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate-docx")
async def generate_docx(
    template: UploadFile = File(...),
    images: List[UploadFile] = File(...),
):
    template_file = None
    try:
        # Validate template file
        if not template.filename:
            raise HTTPException(status_code=400, detail="Template filename is required")
        
        # Create a unique temporary filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        template_file = f"temp_template_{timestamp}.docx"
        
        # Save template to temporary file
        try:
            with open(template_file, "wb") as f:
                f.write(await template.read())
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to save template file: {str(e)}")
        
        # Validate images
        if not images:
            raise HTTPException(status_code=400, detail="At least one image is required")
        
        # Determine which part we're generating based on template filename
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
        
        # Return the DOCX bytes directly as a streaming response
        return StreamingResponse(
            io.BytesIO(docx_bytes),
            media_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")
    finally:
        # Clean up temporary file
        if template_file and os.path.exists(template_file):
            try:
                os.remove(template_file)
            except Exception as e:
                print(f"Warning: Failed to remove temporary file {template_file}: {str(e)}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000) 