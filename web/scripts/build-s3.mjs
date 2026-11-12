// S3 정적 웹사이트용 미리보기 빌드 → dist/s3
// WAS 없이 소개 페이지만 공개할 때 쓴다. nginx가 하던 일을 S3 키 이름으로 대신한다.
//   · /about → nginx try_files $uri.html 대신, 확장자 없는 키(about)도 함께 올린다 (deploy-s3.sh가 text/html로 올림)
//   · /api/notices, /api/notices/{id} → 지금 시드 데이터로 만든 JSON 파일 (읽기 전용 스냅숏)
//   · /app/ → 로그인·예약은 WAS가 필요하므로 「미리보기 안내」 페이지
//   · 404.html → S3 오류 문서
import { spawn } from 'node:child_process';
import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { buildSite, createRenderer, root } from './build-site.mjs';

const out = path.join(root, 'dist', 's3');
const PORT = Number(process.env.SNAPSHOT_PORT || 8095);

await rm(out, { recursive: true, force: true });
const pages = await buildSite(out);

// 확장자 없는 사본 (index.html 제외)
for (const file of pages.filter((f) => f !== 'index.html')) {
  await cp(path.join(out, file), path.join(out, path.basename(file, '.html')));
}

// 미리보기 전용 페이지
const render = await createRenderer();
const previewDir = path.join(root, 'site', 'preview');
await mkdir(path.join(out, 'app'), { recursive: true });
await writeFile(path.join(out, 'app', 'index.html'), render(await readFile(path.join(previewDir, 'app.html'), 'utf8'), 'app', 'preview/app.html'));
await writeFile(path.join(out, '404.html'), render(await readFile(path.join(previewDir, '404.html'), 'utf8'), '404', 'preview/404.html'));

// 공지 스냅숏: 모의 서버를 잠깐 띄워 시드 공지를 그대로 받아 온다
const server = spawn(process.execPath, [path.join(root, 'server', 'mock-server.mjs')], {
  env: { ...process.env, PORT: String(PORT), LATENCY_MS: '0' },
  stdio: ['ignore', 'pipe', 'inherit'],
});
try {
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('모의 서버가 시작되지 않았습니다')), 10_000);
    server.stdout.on('data', (d) => { if (String(d).includes('[mock] http')) { clearTimeout(timer); resolve(); } });
    server.on('exit', (code) => reject(new Error(`모의 서버 종료 (코드 ${code}) — 포트 ${PORT}가 사용 중인지 확인하세요`)));
  });
  const base = `http://localhost:${PORT}`;
  const list = await (await fetch(`${base}/api/notices`)).json();
  await mkdir(path.join(out, 'api', 'notices'), { recursive: true });
  await writeFile(path.join(out, 'api', 'notices.json'), JSON.stringify(list));
  for (const n of list) {
    const detail = await (await fetch(`${base}/api/notices/${n.noticeId}`)).json();
    await writeFile(path.join(out, 'api', 'notices', `${n.noticeId}.json`), JSON.stringify(detail));
  }
  console.log(`s3: 공지 ${list.length}건 스냅숏`);
} finally {
  server.kill();
}

const count = async (dir) => (await readdir(dir, { recursive: true, withFileTypes: true })).filter((e) => e.isFile()).length;
console.log(`s3: ${await count(out)}개 파일 → ${path.relative(root, out)}`);
