const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { Readable } = require('stream');

const app = express();
const PORT = 8080;
const VIDEOS_DIR = 'C:\\Videos';

app.use(cors());

// 1. Google Drive 파일 목록 조회 및 캐싱 트리거
app.get('/list', async (req, res) => {
  const { folderId, access_token, keep_ids, folderName } = req.query;
  const apiKey = 'AIzaSyCgjlRcgzTYBAf_21P-AJTSLTYlFvadavI';
  
  let url = `https://www.googleapis.com/drive/v3/files?q='${folderId}'+in+parents&fields=files(id,name,mimeType,webContentLink)&supportsAllDrives=true&includeItemsFromAllDrives=true`;
  if (access_token) {
    // Auth header used
  } else if (apiKey) {
    url += `&key=${apiKey}`;
  }

  try {
    const headers = { 'User-Agent': 'Mozilla/5.0' };
    if (access_token) {
      headers['Authorization'] = `Bearer ${access_token}`;
    }

    console.log(`[Node Server] Fetching files in folder: ${folderId}`);
    const listResponse = await fetch(url, { headers });
    
    if (!listResponse.ok) {
      throw new Error(`Google API returned status ${listResponse.status}`);
    }

    const data = await listResponse.json();
    const jsonBytes = JSON.stringify(data);

    // 디버그 리스트 저장
    if (!fs.existsSync(VIDEOS_DIR)) {
      fs.mkdirSync(VIDEOS_DIR, { recursive: true });
    }
    fs.writeFileSync(path.join(VIDEOS_DIR, 'debug_list.json'), jsonBytes);

    // 백그라운드 동기화 스크립트 실행 (PowerShell 비동기 백그라운드 프로세스)
    if (access_token && keep_ids) {
      const syncScript = path.join(__dirname, 'sync_videos.ps1');
      const folderNameArg = folderName || folderId;
      
      console.log(`[Node Server] Triggering background sync for: ${folderNameArg}`);
      const ps = spawn('powershell.exe', [
        '-ExecutionPolicy', 'Bypass',
        '-File', syncScript,
        '-folderId', folderId,
        '-accessToken', access_token,
        '-keepIds', keep_ids,
        '-folderName', folderNameArg
      ], {
        detached: true,
        stdio: 'ignore'
      });
      ps.unref(); // 백그라운드에서 부모 독립으로 계속 돌게 함
    }

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.send(jsonBytes);
  } catch (error) {
    console.error('[Node Server] Error in /list:', error.message);
    res.status(500).send(`Error listing drive: ${error.message}`);
  }
});

// 2. 비디오 프록시 스트리밍 및 로컬 재생 자동 감지
app.get('/proxy', async (req, res) => {
  const { id, type, access_token } = req.query;

  if (type === 'video') {
    const localFile = findFileRecursive(VIDEOS_DIR, `${id}.mp4`);
    if (localFile) {
      console.log(`[Node Server] Serving LOCAL video for ${id}`);
      return serveLocalFile(localFile, req, res);
    }
  }

  try {
    let url;
    if (type === 'video') {
      url = access_token
        ? `https://www.googleapis.com/drive/v3/files/${id}?alt=media&supportsAllDrives=true`
        : `https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t`;
    } else {
      url = `https://lh3.googleusercontent.com/d/${id}=w1280`;
    }

    await proxyRequest(url, req, res, access_token, type === 'video');
  } catch (error) {
    console.error('[Node Server] Error proxying:', error.message);
    if (!res.headersSent) {
      res.status(500).send(`Error proxying: ${error.message}`);
    }
  }
});

// 3. 로컬 파일 제공 API
app.get('/local/:filename', (req, res) => {
  const filename = req.params.filename;
  const localFile = findFileRecursive(VIDEOS_DIR, filename);
  if (localFile) {
    serveLocalFile(localFile, req, res);
  } else {
    res.status(404).send('Not Found');
  }
});

// 4. 로컬 비디오 목록 API
app.get('/api/videos', (req, res) => {
  const filesList = [];
  if (fs.existsSync(VIDEOS_DIR)) {
    const files = getFilesRecursive(VIDEOS_DIR, '.mp4');
    files.forEach(f => {
      filesList.push({
        name: path.basename(f),
        url: `/local/${path.basename(f)}`
      });
    });
  }
  res.json(filesList);
});

// 5. 정적 HTML/CSS/JS 파일 매핑 및 폴백
app.use((req, res) => {
  let filepath = req.path === '/' ? '/index.html' : req.path;
  const localPath = path.join(__dirname, filepath);
  
  if (fs.existsSync(localPath) && fs.statSync(localPath).isFile()) {
    // MIME 타입 설정
    const ext = path.extname(localPath).toLowerCase();
    let contentType = 'application/octet-stream';
    if (ext === '.html' || ext === '.htm') contentType = 'text/html; charset=utf-8';
    else if (ext === '.css') contentType = 'text/css';
    else if (ext === '.js') contentType = 'application/javascript';
    else if (ext === '.png') contentType = 'image/png';
    else if (ext === '.jpg' || ext === '.jpeg') contentType = 'image/jpeg';
    else if (ext === '.mp3') contentType = 'audio/mpeg';
    else if (ext === '.mp4') contentType = 'video/mp4';

    res.setHeader('Content-Type', contentType);
    res.sendFile(localPath);
  } else {
    res.status(404).send('404 Not Found');
  }
});

// --- Helper 함수 ---

function findFileRecursive(dir, filename) {
  if (!fs.existsSync(dir)) return null;
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      const found = findFileRecursive(fullPath, filename);
      if (found) return found;
    } else if (file === filename) {
      return fullPath;
    }
  }
  return null;
}

function getFilesRecursive(dir, ext) {
  let results = [];
  if (!fs.existsSync(dir)) return results;
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    if (fs.statSync(fullPath).isDirectory()) {
      results = results.concat(getFilesRecursive(fullPath, ext));
    } else if (path.extname(file).toLowerCase() === ext) {
      results.push(fullPath);
    }
  }
  return results;
}

function serveLocalFile(filePath, req, res) {
  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, "").split("-");
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunksize = (end - start) + 1;
    const file = fs.createReadStream(filePath, { start, end });
    const head = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(206, head);
    file.pipe(res);
  } else {
    const head = {
      'Content-Length': fileSize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(200, head);
    fs.createReadStream(filePath).pipe(res);
  }
}

async function proxyRequest(url, clientReq, clientRes, accessToken, isVideo) {
  const headers = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' };
  if (accessToken && isVideo) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }
  if (clientReq.headers.range && isVideo) {
    headers['Range'] = clientReq.headers.range;
  }

  try {
    const response = await fetch(url, { headers, redirect: 'follow' });
    clientRes.status(response.status);
    
    response.headers.forEach((val, key) => {
      const lowerKey = key.toLowerCase();
      if (['content-type', 'content-length', 'content-range', 'accept-ranges'].includes(lowerKey)) {
        clientRes.setHeader(key, val);
      }
    });

    if (response.body) {
      Readable.fromWeb(response.body).pipe(clientRes);
    } else {
      clientRes.end();
    }
  } catch (err) {
    console.error('[Node Proxy] Error:', err.message);
    if (!clientRes.headersSent) {
      clientRes.status(500).send('Error proxying data');
    }
  }
}

app.listen(PORT, () => {
  console.log(`[Node Server] Running on http://localhost:${PORT}`);
});
