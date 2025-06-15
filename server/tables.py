from docx import Document
from docx.shared import Pt, Inches

def create_iib_docx(systems, output_path):
    doc = Document(r'C:/Users/User/Documents/SOIDProject/assets/II_b.docx')
    for sys in systems:
        table = doc.add_table(rows=8, cols=3)
        table.style = 'Table Grid'
        table.autofit = False  # Prevent auto-resizing

        table.cell(0, 0).merge(table.cell(0, 1))
        table.cell(0, 0).text = 'NAME OF INFORMATION SYSTEM/ SUB-SYSTEM'
        table.cell(0, 2).text = sys.get('name_of_system', '')

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

        table.cell(2, 0).merge(table.cell(2, 1))
        table.cell(2, 0).text = 'STATUS'
        table.cell(2, 2).text = sys.get('status', '')

        table.cell(3, 0).merge(table.cell(3, 1))
        table.cell(3, 0).text = 'DEVELOPMENT STRATEGY'
        table.cell(3, 2).text = sys.get('development_strategy', '')

        table.cell(4, 0).merge(table.cell(4, 1))
        table.cell(4, 0).text = 'COMPUTING SCHEME'
        table.cell(4, 2).text = sys.get('computing_scheme', '')

        table.cell(5, 0).merge(table.cell(6, 0))
        table.cell(5, 0).text = 'USERS'
        table.cell(5, 1).text = 'INTERNAL'
        internal_users = sys.get('users_internal', [])
        if isinstance(internal_users, str):
            internal_users = [internal_users]
        table.cell(5, 2).text = '\n'.join(internal_users)

        table.cell(6, 1).text = 'EXTERNAL'
        table.cell(6, 2).text = sys.get('users_external', '')

        table.cell(7, 0).merge(table.cell(7, 1))
        table.cell(7, 0).text = 'OWNER'
        table.cell(7, 2).text = sys.get('owner', '')

        # Set the width of each column
        col1_width = Inches(1.75)   # 4.44 cm
        col2_width = Inches(1.5)    # Example value, adjust as needed
        col3_width = Inches(6.19)   # 18.26 cm
        for i, row in enumerate(table.rows):
            # For USERS row label, set to 2.6 inches
            if i == 5:
                row.cells[0].width = Inches(2.6)
            else:
                row.cells[0].width = col1_width
            row.cells[1].width = col2_width
            row.cells[2].width = col3_width

        doc.add_paragraph()
    doc.save(output_path)

def create_iic_docx(databases, output_path):
    doc = Document(r'C:/Users/User/Documents/SOIDProject/assets/II_c.docx')
    for db in databases:
        table = doc.add_table(rows=8, cols=3)
        table.style = 'Table Grid'
        table.autofit = False

        table.cell(0, 0).merge(table.cell(0, 1))
        table.cell(0, 0).text = 'NAME OF DATABASE'
        table.cell(0, 2).text = db.get('name_of_database', '')

        table.cell(1, 0).merge(table.cell(1, 1))
        table.cell(1, 0).text = 'GENERAL CONTENTS/DESCRIPTION'
        cell = table.cell(1, 2)
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

        table.cell(2, 0).merge(table.cell(2, 1))
        table.cell(2, 0).text = 'STATUS'
        table.cell(2, 2).text = db.get('status', '')

        table.cell(3, 0).merge(table.cell(3, 1))
        table.cell(3, 0).text = 'INFORMATION SYSTEMS SERVED'
        table.cell(3, 2).text = db.get('info_systems_served', '')

        table.cell(4, 0).merge(table.cell(4, 1))
        table.cell(4, 0).text = 'DATA ARCHIVING/STORAGE MEDIA'
        table.cell(4, 2).text = db.get('data_archiving', '')

        # USERS row (INTERNAL)
        table.cell(5, 0).text = 'USERS'
        table.cell(5, 1).text = 'INTERNAL'
        internal_users = db.get('users_internal', [])
        if isinstance(internal_users, str):
            internal_users = [internal_users]
        table.cell(5, 2).text = '\n'.join(internal_users)

        # USERS row (EXTERNAL)
        table.cell(6, 0).text = ''
        table.cell(6, 1).text = 'EXTERNAL'
        table.cell(6, 2).text = db.get('users_external', '')

        # OWNER row
        table.cell(7, 0).text = 'OWNER'
        table.cell(7, 1).text = ''
        table.cell(7, 2).text = db.get('owner', '')

        # Set the width of each column
        col1_width = Inches(1.75)   # 4.44 cm
        col2_width = Inches(1.5)    # Example value, adjust as needed
        col3_width = Inches(6.19)   # 15.73 cm
        for i, row in enumerate(table.rows):
            if i == 5:
                row.cells[0].width = Inches(2.6)
            else:
                row.cells[0].width = col1_width
            row.cells[1].width = col2_width
            row.cells[2].width = col3_width

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
