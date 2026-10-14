import { validateTurn, decodeWavBase64, coachPrompt } from "./policy.ts";
function check(ok: unknown, msg: string) { if (!ok) throw new Error(msg); }
Deno.test("audio consent and bounded payload required", () => {
  const base = { providerConsent:true, microphoneConsent:true, language:"no", tone:"motivating", audioBase64:"A".repeat(150) };
  check(validateTurn(base)?.language === "no", "valid input");
  check(validateTurn({ ...base, providerConsent:false }) === null, "provider consent");
  check(validateTurn({ ...base, microphoneConsent:false }) === null, "mic consent");
  check(validateTurn({ ...base, language:"zz" }) === null, "language");
  check(validateTurn({ ...base, audioBase64:"A".repeat(520_001) }) === null, "size cap");
  check(validateTurn({ providerConsent:true, language:"no",tone:"balanced",text:"Hvordan går det?" })?.text, "text option");
});
Deno.test("wave validation rejects arbitrary data", () => {
  check(decodeWavBase64(btoa("plain text")) === null, "not a wave");
  const wav=new Uint8Array(44+3200);
  wav.set(new TextEncoder().encode("RIFF"),0);
  wav.set(new TextEncoder().encode("WAVE"),8);
  wav.set(new TextEncoder().encode("fmt "),12);
  wav.set(new TextEncoder().encode("data"),36);
  const dv=new DataView(wav.buffer);
  dv.setUint32(16,16,true);
  dv.setUint16(20,1,true);
  dv.setUint16(22,1,true);
  dv.setUint32(24,16000,true);
  dv.setUint16(34,16,true);
  dv.setUint32(40,3200,true);
  let b64="";for(let i=0;i<wav.length;i++)b64+=String.fromCharCode(wav[i]);
  check(decodeWavBase64(btoa(b64))?.length === wav.length, "valid PCM wave");
});
Deno.test("pilot prompt forbids false workout and health claims",()=>{
  const p=coachPrompt("no","motivating");
  for(const x of ["Norwegian Bokmål","NO verified live workout data","Never invent","chest pain"])check(p.includes(x),x);
});
