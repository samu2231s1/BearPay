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
  let { data:profile, error:profileError } = await db.from('profiles').select('*').eq('id',data.user.id).maybeSingle();
  if (profileError) throw Object.assign(new Error('Não foi possível carregar o perfil. Confirme se o schema.sql foi executado no Supabase.'), { status:500 });
  if (!profile) {
    const metadata = data.user.user_metadata || {};
    const isAdmin = process.env.ADMIN_EMAIL?.trim().toLowerCase() === data.user.email?.trim().toLowerCase();
    const created = await db.from('profiles').insert({
      id: data.user.id,
      email: data.user.email,
      full_name: metadata.full_name || data.user.email?.split('@')[0] || 'Conta BearPay',
      role: isAdmin ? 'admin' : 'merchant',
      kyc_tier: metadata.kyc_tier === 'kyc2' ? 'kyc2' : 'kyc1',
      kyc_status: 'not_submitted'
    }).select('*').single();
    if (created.error) throw Object.assign(new Error(`Não foi possível criar o perfil: ${created.error.message}`), { status:500 });
    profile = created.data;
  }
  return { user:data.user, profile, db };
}
export function assertAdmin(profile) { if (profile.role !== 'admin') throw Object.assign(new Error('Acesso restrito ao administrador'), { status:403 }); }

