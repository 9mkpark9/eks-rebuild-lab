import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 예약·관리자 화면(SPA). nginx의 location /app/ 이 dist/app 을 그대로 제공한다 (부록 E.3).
// 개발 중에는 /api 와 소개 페이지 자산(/assets)을 모의 서버로 넘긴다.
const MOCK = process.env.MOCK_URL ?? 'http://localhost:8090';

export default defineConfig({
  root: 'app',
  base: '/app/',
  plugins: [react()],
  build: {
    outDir: '../dist/app',
    emptyOutDir: true,
  },
  server: {
    fs: { allow: ['..'] },
    proxy: {
      '/api': MOCK,
      '/assets': MOCK,
    },
  },
});
