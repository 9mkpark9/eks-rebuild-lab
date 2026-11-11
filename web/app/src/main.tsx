import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '../../site/assets/css/base.css';
import '../../site/assets/css/board-shell.css';
import './app.css';
import './board-app.css';
import App from './App';
import { AuthProvider } from './auth';
import { ToastProvider } from './ui';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ToastProvider>
      <AuthProvider>
        <App />
      </AuthProvider>
    </ToastProvider>
  </StrictMode>,
);
