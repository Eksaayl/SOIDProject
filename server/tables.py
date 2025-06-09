from docx import Document
from docx.shared import Pt

def create_iib_docx(systems, output_path):
    doc = Document('server/template_iii.docx')
    for sys in systems:
        table = doc.add_table(rows=8, cols=3)
        table.style = 'Table Grid'

        # Row 1: NAME OF INFORMATION SYSTEM/ SUB-SYSTEM
        table.cell(0, 0).merge(table.cell(0, 1))
        table.cell(0, 0).text = 'NAME OF INFORMATION SYSTEM/ SUB-SYSTEM'
        table.cell(0, 2).text = sys.get('name_of_system', '')

        # Row 2: DESCRIPTION (as bullet list)
        table.cell(1, 0).merge(table.cell(1, 1))
        table.cell(1, 0).text = 'DESCRIPTION'
        cell = table.cell(1, 2)
        for para in list(cell.paragraphs):
            p = para._element
            p.getparent().remove(p)
        value = sys.get('description', [])
        if isinstance(value, str):
            value = [v.strip() for v in value.split('\n') if v.strip()]
        for item in value:
            p = cell.add_paragraph(item, style='List Bullet')
            p.paragraph_format.left_indent = Pt(0)
            cell.add_paragraph('')

        # Row 3: STATUS
        table.cell(2, 0).merge(table.cell(2, 1))
        table.cell(2, 0).text = 'STATUS'
        table.cell(2, 2).text = sys.get('status', '')

        # Row 4: DEVELOPMENT STRATEGY
        table.cell(3, 0).merge(table.cell(3, 1))
        table.cell(3, 0).text = 'DEVELOPMENT STRATEGY'
        table.cell(3, 2).text = sys.get('development_strategy', '')

        # Row 5: COMPUTING SCHEME
        table.cell(4, 0).merge(table.cell(4, 1))
        table.cell(4, 0).text = 'COMPUTING SCHEME'
        table.cell(4, 2).text = sys.get('computing_scheme', '')

        # Row 6 & 7: USERS (with internal/external split)
        table.cell(5, 0).merge(table.cell(6, 0))
        table.cell(5, 0).text = 'USERS'
        table.cell(5, 1).text = 'INTERNAL'
        internal_users = sys.get('users_internal', [])
        if isinstance(internal_users, str):
            internal_users = [internal_users]
        table.cell(5, 2).text = '\n'.join(internal_users)
        table.cell(6, 1).text = 'EXTERNAL'
        table.cell(6, 2).text = sys.get('users_external', '')

        # Row 8: OWNER
        table.cell(7, 0).merge(table.cell(7, 1))
        table.cell(7, 0).text = 'OWNER'
        table.cell(7, 2).text = sys.get('owner', '')

        doc.add_paragraph()
    doc.save(output_path)

def create_iic_docx(databases, output_path):
    doc = Document('server/template_iii.docx')
    for db in databases:
        table = doc.add_table(rows=8, cols=3)
        table.style = 'Table Grid'

        # Row 1: NAME OF DATABASE
        table.cell(0, 0).merge(table.cell(0, 1))
        table.cell(0, 0).text = 'NAME OF DATABASE'
        table.cell(0, 2).text = db.get('name_of_database', '')

        # Row 2: GENERAL CONTENTS/DESCRIPTION (as bullet list)
        table.cell(1, 0).merge(table.cell(1, 1))
        table.cell(1, 0).text = 'GENERAL CONTENTS/DESCRIPTION'
        cell = table.cell(1, 2)
        # Remove any existing paragraphs
        for para in list(cell.paragraphs):
            p = para._element
            p.getparent().remove(p)
        value = db.get('general_contents', [])
        if isinstance(value, str):
            value = [v.strip() for v in value.split('\n') if v.strip()]
        for item in value:
            p = cell.add_paragraph(item, style='List Bullet')
            p.paragraph_format.left_indent = Pt(0)
            cell.add_paragraph('')

        # Row 3: STATUS
        table.cell(2, 0).merge(table.cell(2, 1))
        table.cell(2, 0).text = 'STATUS'
        table.cell(2, 2).text = db.get('status', '')

        # Row 4: INFORMATION SYSTEMS SERVED
        table.cell(3, 0).merge(table.cell(3, 1))
        table.cell(3, 0).text = 'INFORMATION SYSTEMS SERVED'
        table.cell(3, 2).text = db.get('info_systems_served', '')

        # Row 5: DATA ARCHIVING/STORAGE MEDIA
        table.cell(4, 0).merge(table.cell(4, 1))
        table.cell(4, 0).text = 'DATA ARCHIVING/STORAGE MEDIA'
        table.cell(4, 2).text = db.get('data_archiving', '')

        # Row 6 & 7: USERS (with internal/external split)
        table.cell(5, 0).merge(table.cell(6, 0))
        table.cell(5, 0).text = 'USERS'
        table.cell(5, 1).text = 'INTERNAL'
        internal_users = db.get('users_internal', [])
        if isinstance(internal_users, str):
            internal_users = [internal_users]
        table.cell(5, 2).text = '\n'.join(internal_users)
        table.cell(6, 1).text = 'EXTERNAL'
        table.cell(6, 2).text = db.get('users_external', '')

        # Row 8: OWNER
        table.cell(7, 0).merge(table.cell(7, 1))
        table.cell(7, 0).text = 'OWNER'
        table.cell(7, 2).text = db.get('owner', '')

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
