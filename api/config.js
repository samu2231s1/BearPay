export default function handler(_req,res){const configured=Boolean(process.env.SUPABASE_URL&&process.env.SUPABASE_ANON_KEY&&process.env.SUPABASE_SERVICE_ROLE_KEY);res.setHeader('Cache-Control','no-store');res.status(200).json({configured,...(configured?{supabaseUrl:process.env.SUPABASE_URL,supabaseAnonKey:process.env.SUPABASE_ANON_KEY}:{})});}

