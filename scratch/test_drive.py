import requests
import json

folder_id = '1rpumueOBAPqU4TKZyOdjBBoUyCDNuurj'
api_key = 'AIzaSyCgjlRcgzTYBAf_21P-AJTSLTYlFvadavI'

url = "https://www.googleapis.com/drive/v3/files"
params = {
    'q': f"'{folder_id}' in parents and trashed = false",
    'key': api_key,
    'fields': 'files(id, name, mimeType)'
}

try:
    response = requests.get(url, params=params)
    print("Status Code:", response.status_code)
    print("Response JSON:")
    print(json.dumps(response.json(), indent=2, ensure_ascii=False))
except Exception as e:
    print("Error:", e)
