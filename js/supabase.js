import { config } from './config.js';
let clientPromise;
export function getSupabase() {
  if (!config.supabaseUrl || !config.supabasePublishableKey) return Promise.resolve(null);
  if (!clientPromise) clientPromise = (async () => {
    const url = new URL(config.supabaseUrl);
    if (url.protocol !== 'https:') throw new Error('Supabase adresi HTTPS olmalı.');
    const { createClient } = await import(config.supabaseSdkUrl);
    return createClient(url.href, config.supabasePublishableKey);
  })().catch(error => { clientPromise = undefined; throw error; });
  return clientPromise;
}
