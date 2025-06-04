from docx import Document
from docx.shared import Pt

def create_iii_b_docx(projects, output_path):
    doc = Document('server/template_iii.docx')
    for project in projects:
        table = doc.add_table(rows=6, cols=2)
        table.style = 'Table Grid'
        fields = [
            ('A.1 NAME/TITLE', project.get('name', '')),
            ('A.2 OBJECTIVES', project.get('objectives', '')),
            ('A.3 DURATION', project.get('duration', '')),
            ('A.4 DELIVERABLES', project.get('deliverables', [])),
            ('A.5 LEAD AGENCY', project.get('lead_agency', '')),
            ('A.6 IMPLEMENTING AGENCIES', project.get('implementing_agencies', '')),
        ]
        for i, (label, value) in enumerate(fields):
            table.cell(i, 0).text = label
            if label == 'A.4 DELIVERABLES':
                cell = table.cell(i, 1)
                for para in list(cell.paragraphs):
                    p = para._element
                    p.getparent().remove(p)
                if isinstance(value, str):
                    value = [v.strip() for v in value.split('\n') if v.strip()]
                for deliverable in value:
                    p = cell.add_paragraph(deliverable, style='List Bullet')
                    p.paragraph_format.left_indent = Pt(0)
                    cell.add_paragraph('')
            else:
                cell = table.cell(i, 1)
                cell.text = value
                if label == 'A.1 NAME/TITLE':
                    for paragraph in cell.paragraphs:
                        for run in paragraph.runs:
                            run.bold = True
        doc.add_paragraph()
    doc.save(output_path)

def create_iii_a_docx(projects, output_path):
    doc = Document('server/template_iii.docx')
    for project in projects:
        table = doc.add_table(rows=4, cols=2)
        table.style = 'Table Grid'
        fields = [
            ('A.1 NAME/TITLE', project.get('name', '')),
            ('A.2 OBJECTIVES', project.get('objectives', '')),
            ('A.3 DURATION', project.get('duration', '')),
            ('A.4 DELIVERABLES', project.get('deliverables', [])),
        ]
        for i, (label, value) in enumerate(fields):
            table.cell(i, 0).text = label
            if label == 'A.4 DELIVERABLES':
                cell = table.cell(i, 1)
                for para in list(cell.paragraphs):
                    p = para._element
                    p.getparent().remove(p)
                if isinstance(value, str):
                    value = [v.strip() for v in value.split('\n') if v.strip()]
                for deliverable in value:
                    p = cell.add_paragraph(deliverable, style='List Bullet')
                    p.paragraph_format.left_indent = Pt(0)
                    cell.add_paragraph('')
            else:
                table.cell(i, 1).text = value
        doc.add_paragraph()
    doc.save(output_path) 