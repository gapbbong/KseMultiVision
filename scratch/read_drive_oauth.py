import os
import datetime
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = [
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/spreadsheets.readonly'
]

def main():
    creds = None
    if os.path.exists('scratch/token.json'):
        creds = Credentials.from_authorized_user_file('scratch/token.json', SCOPES)
    
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                creds = None
        if not creds:
            client_secret_file = 'client_secret_476208201237-9cvftec2m6g60r07jfe88akitbkb7869.apps.googleusercontent.com.json'
            flow = InstalledAppFlow.from_client_secrets_file(client_secret_file, SCOPES)
            creds = flow.run_local_server(host='localhost', port=8080)
        os.makedirs('scratch', exist_ok=True)
        with open('scratch/token.json', 'w') as token:
            token.write(creds.to_json())

    drive_service = build('drive', 'v3', credentials=creds)
    sheets_service = build('sheets', 'v4', credentials=creds)

    # 2026학년도 폴더 ID 고정
    folder_2026_id = '1AdtB1ed5T3kAdwEZZN7EWVKUwK0-Q0bV'
    
    file_results = drive_service.files().list(
        q=f"'{folder_2026_id}' in parents and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
        fields="files(id, name)"
    ).execute()
    sheets = file_results.get('files', [])
    
    output_lines = []
    output_lines.append("=== 2026학년도 주간 전달사항 및 대표 일정 ===")
    
    for sheet in sorted(sheets, key=lambda x: x['name']):
        output_lines.append(f"\n파일: {sheet['name']} (ID: {sheet['id']})")
        try:
            sheet_meta = sheets_service.spreadsheets().get(spreadsheetId=sheet['id']).execute()
            sheets_in_doc = sheet_meta.get('sheets', [])
            
            for s in sheets_in_doc:
                sheet_title = s['properties']['title']
                range_name = f"'{sheet_title}'!A1:I40"
                
                val_res = sheets_service.spreadsheets().values().get(
                    spreadsheetId=sheet['id'], range=range_name
                ).execute()
                values = val_res.get('values', [])
                
                if not values:
                    continue
                
                output_lines.append(f"  [시트 탭] {sheet_title}")
                
                for idx, row in enumerate(values):
                    # Only record non-empty rows
                    non_empty = [val for val in row if val.strip()]
                    if non_empty:
                        output_lines.append(f"    행 {idx}: {row}")
                        
        except Exception as ex:
            output_lines.append(f"    파일 처리 중 에러 발생 {sheet['name']}: {ex}")

    with open('scratch/result.txt', 'w', encoding='utf-8') as f:
        f.write('\n'.join(output_lines))
    print("Parsing completed! Results saved to scratch/result.txt")

if __name__ == '__main__':
    main()
