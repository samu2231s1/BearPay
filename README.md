# BearPay

Gateway Pix full-stack com landing page, painel do lojista, KYC em dois níveis, fila administrativa, Supabase e funções serverless para Vercel.

## O que está pronto

- Landing BearPay preservada em `index.html.html`, com CTAs ligados a cadastro/login.
- Cadastro e login via Supabase Auth.
- KYC 1 (Lunar/PixGhost): acesso imediato, 8% + R$ 2,50 por venda e 9% no saque.
- KYC 2 (Mistic): frente, verso e selfie com documento; aprovação manual; 5% + R$ 1,80 por venda e 5% + R$ 1,00 no saque.
- Painel com visão geral, vendas, extrato, gráficos, cobrança Pix, produtos, checkouts, cupons, webhooks, MED, tickets e configurações.
- Saques reservam saldo atomicamente e entram em fila. O provedor só é chamado depois da aprovação do admin.
- Aviso de prazo: normalmente até 3 horas, podendo levar até 72 horas.
- Webhooks Lunar com HMAC e Mistic com segredo na URL, processados de forma idempotente.
- Documentos KYC em bucket privado com URLs assinadas de 5 minutos para o admin.
- Registro de auditoria e razão financeira (`ledger_entries`).
- Modo demonstração automático enquanto o Supabase não estiver configurado.

## Configurar o Supabase

1. Crie um projeto no Supabase.
2. Abra **SQL Editor**, cole todo o arquivo [`supabase/schema.sql`](supabase/schema.sql) e execute.
3. Em **Authentication → URL Configuration**, defina a URL do site e adicione `https://SEU-DOMINIO.vercel.app/**` aos redirects.
4. Crie seu usuário pela tela da BearPay.
5. Promova o primeiro administrador no SQL Editor:

```sql
update public.profiles
set role = 'admin'
where email = 'seu-admin@dominio.com';
```

O bucket `kyc-documents` é criado pelo próprio schema e permanece privado.

## Onde colocar as APIs Lunar e Mistic

No Vercel, entre em **Project → Settings → Environment Variables** e cadastre as variáveis do arquivo `.env.example`.

```text
SUPABASE_URL=https://SEU-PROJETO.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...

LUNARPAY_API_KEY=...
MISTICPAY_CLIENT_ID=pk_...
MISTICPAY_CLIENT_SECRET=sk_...

APP_URL=https://SEU-DOMINIO.vercel.app
WEBHOOK_SHARED_SECRET=um-segredo-longo-e-aleatorio
```

As credenciais dos gateways são lidas apenas dentro de `api/_lib/providers.js`. Elas nunca são enviadas ao navegador. Use a chave de acesso `pk_`/`sk_` da Mistic com os escopos `TRANSACTION_CREATE`, `TRANSACTION_READ`, `WITHDRAW_CREATE`, `BALANCE_READ`, `MED_READ` e `MED_RESPOND`. A autenticação legada `ci/cs` foi descontinuada em 30/09/2026 e não é usada neste projeto.

Na Lunar, habilite manualmente o envio de Pix em **Configurações → Desenvolvedor/API**, pois ele vem desativado por padrão.

## Deploy no Vercel

```bash
npm install
npm run check
vercel
```

Depois de cadastrar as variáveis, faça um novo deploy. As URLs de webhook são montadas automaticamente:

- `https://SEU-DOMINIO.vercel.app/api/webhooks/lunar`
- `https://SEU-DOMINIO.vercel.app/api/webhooks/mistic?secret=...`

Defina `APP_URL` exatamente com o domínio usado em produção. A Mistic não tem sandbox; valide a integração com valores baixos. Se a conta Mistic usa lista de IPs autorizados, lembre que funções comuns da Vercel não possuem um IP de saída fixo; nesse caso, use Vercel Secure Compute/NAT ou deixe a lista vazia conforme sua política de segurança.

## Fluxos financeiros

### Cobrança

1. O backend escolhe Lunar para KYC 1 ou Mistic para KYC 2 aprovado.
2. A transação local é criada antes da chamada externa.
3. O QR Code e o Pix copia-e-cola são salvos.
4. O webhook confirmado credita somente o valor líquido (`amount - fee`).
5. `webhook_events` impede crédito duplicado.

### Saque

1. A solicitação reserva `valor + taxa` em uma função SQL com lock de saldo.
2. O saque fica como `pending_admin`.
3. O admin aprova pelo painel.
4. A chamada externa usa idempotência: ID local na Lunar e `X-Idempotency-Key` na Mistic.
5. O webhook conclui o estado do saque.

Antes de abrir pagamentos reais ao público, faça uma revisão jurídica/compliance, configure Política de Privacidade e Termos, defina retenção dos documentos KYC e teste os webhooks com pagamentos de baixo valor.

## Estrutura

```text
index.html.html          landing original
dashboard.html           painel e autenticação
checkout.html            checkout público
assets/                   interface e interações
api/action.js             API autenticada e pública
api/webhooks/             callbacks dos gateways
api/_lib/                 Supabase, taxas e adapters
supabase/schema.sql       banco, RLS, Storage e funções atômicas
vercel.json               rotas e headers
```

