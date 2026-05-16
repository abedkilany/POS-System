export async function GET() {
  return Response.json({ ok: true, service: 'store-manager-pro-api', generatedAt: new Date().toISOString() });
}
