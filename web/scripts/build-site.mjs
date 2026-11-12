// 소개 페이지 빌드: site/pages/*.html 에 공통 조각(partials)과 고객사 설정(clinic.config.json)을 채워
// dist/site 에 정적 HTML로 내보낸다. nginx는 이 결과를 WAS 없이 바로 응답한다(부록 E.3 location /).
// 고객사가 바뀌면 clinic.config.json 과 이미지만 바꿔 다시 빌드한다.
import { readFile, writeFile, readdir, mkdir, rm, cp } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const siteDir = path.join(root, 'site');

const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

/** 공통 조각과 설정값을 읽어 페이지를 그리는 함수를 돌려준다 (S3 미리보기 빌드도 함께 쓴다) */
export async function createRenderer() {
  const config = JSON.parse(await readFile(path.join(root, 'clinic.config.json'), 'utf8'));
  const vars = {
    ...config,
    phoneTel: config.phone.replace(/[^0-9]/g, ''),
    year: String(new Date().getFullYear()),
    hours: { ...config.hours, closedDays: config.hours.closedDays.join(',') },
  };
  const lookup = (key) => key.split('.').reduce((v, k) => (v == null ? undefined : v[k]), vars);

  const partials = {};
  for (const f of await readdir(path.join(siteDir, 'partials'))) {
    partials[path.basename(f, '.html')] = await readFile(path.join(siteDir, 'partials', f), 'utf8');
  }

  return function render(html, name, file = name) {
    html = html.replace(/<!--\s*@include\s+(\w+)\s*-->/g, (_, p) => {
      if (!(p in partials)) throw new Error(`${file}: 없는 조각 ${p}`);
      return partials[p].trim();
    });
    // 현재 페이지 메뉴 표시
    html = html.replaceAll(`data-nav="${name}"`, `data-nav="${name}" aria-current="page"`);
    // {{path.to.value}} 또는 {{list|li}} (배열을 <li> 목록으로)
    return html.replace(/\{\{\s*([\w.]+)(\|li)?\s*\}\}/g, (_, key, filter) => {
      const v = lookup(key);
      if (v === undefined) throw new Error(`${file}: 설정에 없는 값 {{${key}}}`);
      if (filter === '|li') return (Array.isArray(v) ? v : [v]).map((x) => `<li>${escapeHtml(x)}</li>`).join('');
      return escapeHtml(v);
    });
  };
}

export async function buildSite(outDir = path.join(root, 'dist', 'site')) {
  const render = await createRenderer();
  await rm(outDir, { recursive: true, force: true });
  await mkdir(outDir, { recursive: true });
  await cp(path.join(siteDir, 'assets'), path.join(outDir, 'assets'), { recursive: true });

  const pages = (await readdir(path.join(siteDir, 'pages'))).filter((f) => f.endsWith('.html'));
  for (const file of pages) {
    const html = await readFile(path.join(siteDir, 'pages', file), 'utf8');
    await writeFile(path.join(outDir, file), render(html, path.basename(file, '.html'), file));
  }
  console.log(`site: ${pages.length}개 페이지 → ${path.relative(root, outDir)}`);
  return pages;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) await buildSite();
