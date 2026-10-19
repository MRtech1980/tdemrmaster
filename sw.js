// Service worker mínimo: solo maneja el mismo origen; Supabase y otros dominios van directo a la red
self.addEventListener("install",function(){self.skipWaiting()});
self.addEventListener("activate",function(e){e.waitUntil(self.clients.claim())});
self.addEventListener("fetch",function(e){
 if(new URL(e.request.url).origin!==self.location.origin)return;
 e.respondWith(fetch(e.request));
});
