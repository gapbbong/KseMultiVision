const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { Readable } = require('stream');

const app = express();
const PORT = 8080;
const VIDEOS_DIR = 'C:\\Videos';

// 전역 에러 핸들러 - 클라이언트 연결 끊김(ECONNRESET) 등으로 서버가 죽지 않도록 방지
process.on('uncaughtException', (err) => {
  console.error('[Node Server] Uncaught Exception (서버 계속 실행):', err.message);
});
process.on('unhandledRejection', (reason) => {
  console.error('[Node Server] Unhandled Rejection (서버 계속 실행):', reason?.message || reason);
});

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

    console.log(`[Node Server] Fetching files in folder: ${folderId} (recursive)`);
    const allFiles = await getFilesInFolderRecursive(folderId, access_token, apiKey);
    const data = { files: allFiles };
    const jsonBytes = JSON.stringify(data);

    // 디버그 리스트 저장
    if (!fs.existsSync(VIDEOS_DIR)) {
      fs.mkdirSync(VIDEOS_DIR, { recursive: true });
    }
    fs.writeFileSync(path.join(VIDEOS_DIR, `debug_list_${folderId}.json`), jsonBytes);

    // 백그라운드 동기화 스크립트 실행 (PowerShell 비동기 백그라운드 프로세스)
    if (access_token && keep_ids) {
      const syncScript = path.join(__dirname, 'sync_videos.ps1');
      const folderNameArg = folderName || folderId;
      
      console.log(`[Node Server] Triggering background sync for: ${folderNameArg}`);
      const psCommand = `& "${syncScript}" -folderId "${folderId}" -accessToken "${access_token}" -keepIds "${keep_ids}" -folderName "${folderNameArg}"`;
      console.log(`[Node Server] Spawn command: powershell.exe -ExecutionPolicy Bypass -Command "${psCommand}"`);
      const ps = spawn('powershell.exe', [
        '-ExecutionPolicy', 'Bypass',
        '-Command', psCommand
      ]);
      ps.stdout.on('data', (data) => {
        console.log(`[Sync stdout: ${folderNameArg}] ${data.toString().trim()}`);
      });
      ps.stderr.on('data', (data) => {
        console.error(`[Sync stderr: ${folderNameArg}] ${data.toString().trim()}`);
      });
      ps.on('error', (err) => {
        console.error(`[Node Server] Failed to start sync process for ${folderNameArg}:`, err.message);
      });
      ps.on('close', (code) => {
        console.log(`[Node Server] Sync process for ${folderNameArg} exited with code ${code}`);
      });
    }

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.send(jsonBytes);
  } catch (error) {
    console.error('[Node Server] Error in /list:', error.message);
    const debugListPath = path.join(VIDEOS_DIR, `debug_list_${folderId}.json`);
    if (fs.existsSync(debugListPath)) {
      console.log(`[Node Server] Fallback: Serving cached debug_list_${folderId}.json`);
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      return res.sendFile(debugListPath);
    }
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
      /*
      if (type === 'video') {
        const fallbackPath = path.join(__dirname, 'fallback.mp4');
        if (fs.existsSync(fallbackPath)) {
          console.log('[Node Server] Fallback: Serving local fallback.mp4');
          return serveLocalFile(fallbackPath, req, res);
        }
      }
      */
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
      const parentDir = path.basename(path.dirname(f));
      filesList.push({
        name: path.basename(f),
        url: `/local/${path.basename(f)}`,
        folder: parentDir
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
    file.on('error', (err) => {
      if (err.code !== 'ERR_STREAM_DESTROYED') {
        console.error('[Node Server] File stream error:', err.message);
      }
    });
    const head = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(206, head);
    file.pipe(res);
    res.on('close', () => file.destroy());
  } else {
    const head = {
      'Content-Length': fileSize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(200, head);
    const stream = fs.createReadStream(filePath);
    stream.on('error', (err) => {
      if (err.code !== 'ERR_STREAM_DESTROYED') {
        console.error('[Node Server] File stream error:', err.message);
      }
    });
    stream.pipe(res);
    res.on('close', () => stream.destroy());
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
    let currentUrl = url;
    let response;
    let redirectCount = 0;

    // Node.js fetch(undici)는 다른 Origin으로 리다이렉트 시 Authorization 헤더를 자동으로 삭제하므로,
    // 구글 드라이브 다운로드 서버(googleusercontent.com)로 리다이렉트될 때 헤더를 강제 유지하기 위해 수동 처리합니다.
    while (redirectCount < 5) {
      response = await fetch(currentUrl, { headers, redirect: 'manual' });
      
      if (response.status >= 300 && response.status < 400) {
        const location = response.headers.get('location');
        if (location) {
          currentUrl = new URL(location, currentUrl).toString();
          redirectCount++;
          console.log(`[Node Proxy] Manually following redirect #${redirectCount} to: ${currentUrl}`);
          continue;
        }
      }
      break;
    }

    const contentType = response.headers.get('content-type') || '';
    if (!response.ok || (isVideo && contentType.includes('text/html'))) {
      throw new Error(`Google returned status ${response.status} with content-type ${contentType}`);
    }
    clientRes.status(response.status);
    
    response.headers.forEach((val, key) => {
      const lowerKey = key.toLowerCase();
      if (['content-type', 'content-length', 'content-range', 'accept-ranges'].includes(lowerKey)) {
        clientRes.setHeader(key, val);
      }
    });

    if (response.body) {
      const readable = Readable.fromWeb(response.body);
      readable.on('error', (err) => {
        // 클라이언트 연결 끊김은 무시, 그 외 에러만 로깅
        if (err.code !== 'ERR_STREAM_DESTROYED' && err.message !== 'terminated') {
          console.error('[Node Proxy] Stream error:', err.message);
        }
      });
      clientRes.on('close', () => readable.destroy());
      readable.pipe(clientRes);
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

async function getFilesInFolderRecursive(folderId, accessToken, apiKey) {
  let allFiles = [];
  let url = `https://www.googleapis.com/drive/v3/files?q='${folderId}'+in+parents+and+trashed=false&fields=files(id,name,mimeType,webContentLink)&supportsAllDrives=true&includeItemsFromAllDrives=true`;
  if (!accessToken && apiKey) {
    url += `&key=${apiKey}`;
  }

  const headers = { 'User-Agent': 'Mozilla/5.0' };
  if (accessToken) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }

  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`Google Drive API returned status ${response.status} for folder ${folderId}`);
  }

  const data = await response.json();
  if (data.files && data.files.length > 0) {
    for (const file of data.files) {
      const name = file.name || '';
      // 1사분면(Movie) 리스팅 시 졸업앨범 야외촬영 관련 폴더/비디오 파일은 제외
      if (name.includes('졸업') || name.includes('앨범') || name.includes('촬영') || name.includes('야외촬영')) {
        console.log(`[Node Server] Skipping graduation album item from sync: ${name}`);
        continue;
      }
      
      // 드론 관련 폴더 및 체육대회 드론 폴더 등은 1사분면 Movie 폴더 리스팅 시 하위 탐색에서 제외
      const droneFolderIds = [
        '1GVcymOsyDYcoVvxt-kF-Q0YZ8E0WlUSf',
        '1BN1QuoCnzzdWAgph5ZD88U1zoLBrWt6L'
      ];
      if (droneFolderIds.includes(file.id) || 
          (file.mimeType === 'application/vnd.google-apps.folder' && 
           (name.includes('드론') || name.toLowerCase().includes('drone') || name.includes('체육대회')))) {
        console.log(`[Node Server] Skipping drone subfolder traversal: ${name} (${file.id})`);
        continue;
      }
      
      if (file.mimeType === 'application/vnd.google-apps.folder') {
        try {
          const subFiles = await getFilesInFolderRecursive(file.id, accessToken, apiKey);
          allFiles = allFiles.concat(subFiles);
        } catch (subErr) {
          console.warn(`[Node Server] Failed to list subfolder ${file.name}:`, subErr.message);
        }
      } else {
        allFiles.push(file);
      }
    }
  }

  return allFiles;
}

app.listen(PORT, () => {
  console.log(`[Node Server] Running on http://localhost:${PORT}`);
});
