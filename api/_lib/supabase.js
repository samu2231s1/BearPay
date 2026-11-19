import { createClient } from '@supabase/supabase-js';

export function adminDb() {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Supabase não configurado');
  return createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession:false, autoRefreshToken:false } });
}
export async function requireUser(req) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i,'');
  if (!token) throw Object.assign(new Error('Não autenticado'), { status:401 });
  const db = adminDb(); const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw Object.assign(new Error('Sessão inválida'), { status:401 });
  const { data:profile, error:profileError } = await db.from('profiles').select('*').eq('id',data.user.id).single();
  if (profileError) throw Object.assign(new Error('Perfil não encontrado'), { status:403 });
  return { user:data.user, profile, db };
}
export function assertAdmin(profile) { if (profile.role !== 'admin') throw Object.assign(new Error('Acesso restrito ao administrador'), { status:403 }); }

