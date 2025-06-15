import os
import io
import base64
import tempfile
import logging
import traceback
from typing import Dict, Any
from docx import Document
from docx.shared import Inches
from docx.oxml import parse_xml
from docx.oxml.ns import qn

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def replace_first_picture_content_control(doc, image_path):
    """
    Replace the first picture content control in the document with the given image.
    """
    ns = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
    for sdt in doc.element.iterfind('.//%ssdt' % ns):
        # Look for a drawing or pict in the content control
        sdt_content = sdt.find(f'{ns}sdtContent')
        if sdt_content is not None:
            found_pic = False
            for descendant in sdt_content.iter():
                if descendant.tag in (f'{ns}drawing', f'{ns}pict'):
                    found_pic = True
                    break
            if found_pic:
                # Remove all children in sdtContent
                for child in list(sdt_content):
                    sdt_content.remove(child)
                from docx.text.paragraph import Paragraph
                from docx.oxml import OxmlElement
                p = OxmlElement('w:p')
                r = OxmlElement('w:r')
                p.append(r)
                sdt_content.append(p)
                para = Paragraph(p, doc)
                run = para.add_run()
                run.add_picture(image_path, width=Inches(6))
                break

def generate_part_ib_docx(data: Dict[str, Any], template_path: str) -> bytes:
    """
    Generate a DOCX file for Part IB using the provided data and template.
    Inserts the image at the paragraph containing the ${organizationalStructure} placeholder.
    
    Args:
        data: Dictionary containing the form data
        template_path: Path to the template DOCX file
        
    Returns:
        bytes: The generated DOCX file as bytes
    """
    logger.debug("Starting document generation")
    logger.debug(f"Template path: {template_path}")
    logger.debug(f"Received data keys: {list(data.keys())}")
    
    try:
        # Check if template exists
        if not os.path.exists(template_path):
            error_msg = f"Template file not found at {template_path}"
            logger.error(error_msg)
            raise FileNotFoundError(error_msg)
            
        # Load the template
        try:
            doc = Document(template_path)
            logger.debug("Template loaded successfully")
        except Exception as e:
            error_msg = f"Error loading template: {str(e)}"
            logger.error(error_msg)
            raise
            
        # --- Replace text placeholders in paragraphs ---
        for paragraph in doc.paragraphs:
            for key, value in data.items():
                if key != 'organizationalStructure':
                    placeholder = f'${{{key}}}'
                    if placeholder in paragraph.text:
                        logger.debug(f"Replacing {placeholder} in paragraph with {value}")
                        paragraph.text = paragraph.text.replace(placeholder, str(value))

        # --- Replace text placeholders in tables ---
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    for key, value in data.items():
                        if key != 'organizationalStructure':
                            placeholder = f'${{{key}}}'
                            if placeholder in cell.text:
                                logger.debug(f"Replacing {placeholder} in table cell with {value}")
                                cell.text = cell.text.replace(placeholder, str(value))
        
        # --- Insert the image at the placeholder paragraph ---
        if 'organizationalStructure' in data and data['organizationalStructure']:
            try:
                image_data = base64.b64decode(data['organizationalStructure'])
                logger.debug(f"Decoded image size: {len(image_data)} bytes")
                
                # Create a temporary file for the image
                with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as temp_img:
                    temp_img.write(image_data)
                    temp_img_path = temp_img.name
                
                logger.debug(f"Created temporary image file at: {temp_img_path}")

                # Find the paragraph with the placeholder and replace it with the image
                found = False
                for i, paragraph in enumerate(doc.paragraphs):
                    if '${organizationalStructure}' in paragraph.text:
                        logger.debug("Found image placeholder in paragraph. Replacing with image.")
                        # Remove the placeholder text
                        paragraph.text = paragraph.text.replace('${organizationalStructure}', '')
                        run = paragraph.add_run()
                        run.add_picture(temp_img_path, width=Inches(8.29), height=Inches(5.27))
                        found = True
                        break
                if not found:
                    logger.warning("Image placeholder not found in document.")
                
                # Clean up the temporary file
                os.unlink(temp_img_path)
                logger.debug("Temporary image file cleaned up")
            except Exception as e:
                error_msg = f"Error processing image: {str(e)}"
                logger.error(error_msg)
                logger.error(traceback.format_exc())
                raise
        else:
            logger.warning("No organizational structure image provided")
        
        # Save the document to bytes
        try:
            docx_bytes = io.BytesIO()
            doc.save(docx_bytes)
            docx_bytes.seek(0)
            logger.debug("Document saved to bytes successfully")
            return docx_bytes.getvalue()
        except Exception as e:
            error_msg = f"Error saving document: {str(e)}"
            logger.error(error_msg)
            logger.error(traceback.format_exc())
            raise
            
    except Exception as e:
        error_msg = f"Error in generate_part_ib_docx: {str(e)}"
        logger.error(error_msg)
        logger.error(traceback.format_exc())
        raise

def format_number(value: str) -> str:
    """
    Format a number string with commas.
    
    Args:
        value: The number string to format
    
    Returns:
        str: Formatted number string or original value if not a number
    """
    if not value or not value.strip():
        return '0'
        
    # Remove any existing commas
    value = value.strip().replace(',', '')
    
    # If the value is not a number, return it as is
    if not value.replace('-', '').replace('.', '').isdigit():
        logger.debug(f"Value '{value}' is not a number, returning as is")
        return value
        
    try:
        # Format with commas
        num = int(float(value))
        return f"{num:,}"
    except (ValueError, TypeError) as e:
        logger.debug(f"Error formatting number '{value}': {str(e)}")
        return value

def process_part_ib_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process the raw form data for Part IB.
    
    Args:
        data: Raw form data from the request
    
    Returns:
        Dict[str, Any]: Processed data ready for document generation
    """
    try:
        logger.debug("Processing Part IB data")
        # Format all numeric fields
        numeric_fields = [
            'mooe', 'co', 'total', 'nicthsProjectCost', 'hsdvProjectCost', 'hecsProjectCost',
            'totalEmployees', 'regionalOffices', 'provincialOffices',
            'coPlantilaPositions', 'coVacant', 'coFilledPlantilaPositions', 
            'coFilledPhysicalPositions', 'coCosws', 'coContractual', 'coTotal',
            'foPlantilaPositions', 'foVacant', 'foFilledPlantilaPositions',
            'foFilledPhysicalPositions', 'foCosws', 'foContractual', 'foTotal'
        ]
        
        processed_data = data.copy()
        
        for field in numeric_fields:
            if field in processed_data:
                processed_data[field] = format_number(processed_data[field])
        
        logger.debug("Data processing completed successfully")
        return processed_data
    except Exception as e:
        logger.error(f"Error in process_part_ib_data: {str(e)}")
        logger.error(traceback.format_exc())
        raise 

def generate_ib_docx(data):
    try:
        # Load the template
        template_path = os.path.join(os.path.dirname(__file__), 'templates', 'part_ib_template.docx')
        doc = Document(template_path)

        # Define replacements
        replacements = {
            '${plannerName}': data.get('plannerName', ''),
            '${plantillaPosition}': data.get('plantillaPosition', ''),
            '${organizationalUnit}': data.get('organizationalUnit', ''),
            '${emailAddress}': data.get('emailAddress', ''),
            '${contactNumbers}': data.get('contactNumbers', ''),
            '${mooe}': data.get('mooe', ''),
            '${co}': data.get('co', ''),
            '${total}': data.get('total', ''),
            '${totalEmployees}': data.get('totalEmployees', ''),
            '${regionalOffices}': data.get('regionalOffices', ''),
            '${provincialOffices}': data.get('provincialOffices', ''),
            '${otherOffices}': data.get('otherOffices', ''),
            '${coPlantilaPositions}': data.get('coPlantilaPositions', ''),
            '${coVacant}': data.get('coVacant', ''),
            '${coFilledPlantilaPositions}': data.get('coFilledPlantilaPositions', ''),
            '${coFilledPhysicalPositions}': data.get('coFilledPhysicalPositions', ''),
            '${coCosws}': data.get('coCosws', ''),
            '${coContractual}': data.get('coContractual', ''),
            '${coTotal}': data.get('coTotal', ''),
            '${foPlantilaPositions}': data.get('foPlantilaPositions', ''),
            '${foVacant}': data.get('foVacant', ''),
            '${foFilledPlantilaPositions}': data.get('foFilledPlantilaPositions', ''),
            '${foFilledPhysicalPositions}': data.get('foFilledPhysicalPositions', ''),
            '${foCosws}': data.get('foCosws', ''),
            '${foContractual}': data.get('foContractual', ''),
            '${foTotal}': data.get('foTotal', ''),
            '${otrFund}': data.get('otrFund', ''),
            '${currDate}': data.get('currDate', ''),
        }

        # Replace placeholders in the document
        for paragraph in doc.paragraphs:
            for key, value in replacements.items():
                if key in paragraph.text:
                    paragraph.text = paragraph.text.replace(key, value)

        # Save the modified document to a temporary file
        temp_path = os.path.join(os.path.dirname(__file__), 'temp', 'part_ib_output.docx')
        os.makedirs(os.path.dirname(temp_path), exist_ok=True)
        doc.save(temp_path)

        return temp_path
    except Exception as e:
        print(f"Error generating Part IB document: {str(e)}")
        raise 