import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({root:'client',plugins:[react()],build:{outDir:'../dist/client',emptyOutDir:true},server:{host:'127.0.0.1',port:5173,strictPort:true,proxy:{'/api':'http://127.0.0.1:5000','/robots.txt':'http://127.0.0.1:5000','/sitemap.xml':'http://127.0.0.1:5000'}}});
