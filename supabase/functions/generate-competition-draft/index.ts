import { createClient } from "npm:@supabase/supabase-js@2.57.4";

type RequestDraft = {
  prompt?: string;
  format?: "league" | "groups" | "cup";
  activities?: string[];
  maxExercises?: number;
};
const ACTIVITY_TYPES = new Set(["running","walking","strength","hiking","cycling","swimming"]);
const allowedStartModes = new Set(["manual","when_ready"]);
const validEnvironment = new Set(["any","outdoor","gym"]);
type CatalogExercise = { id:string; title:string; activity_type:string };
function json(data:unknown,status=200):Response {
  return new Response(JSON.stringify(data),{
    status,
    headers: {"Content-Type":"application/json;charset=utf-8","Cache-Control":"no-store"}
  });
}
function clean(value:unknown,n:number):string {
  return typeof value==="string" ? value.trim().slice(0,n) : "";
}

Deno.serve(async (request:Request)=>{
  if(request.method!=="POST") return json({error:"Method not allowed"},405);
  const authorization=request.headers.get("Authorization")??"";
  if(!authorization.startsWith("Bearer ")) return json({error:"Sign-in required"},401);
  const url=Deno.env.get("SUPABASE_URL");
  const role=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const groq=Deno.env.get("GROQ_API_KEY");
  if(!url||!role||!groq) return json({error:"Coach is temporarily unavailable"},503);
  const admin=createClient(url,role,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await admin.auth.getUser(
    authorization.substring(7).trim());
  if(userError||!user) return json({error:"Session expired"},401);
  let body:RequestDraft;
  try {body=await request.json() as RequestDraft;}
  catch{return json({error:"Invalid input"},400);}
  const prompt=clean(body.prompt,500);
  const format=body.format;
  const allowed=Array.from(new Set(
    (Array.isArray(body.activities)?body.activities:[]).filter(
      (item):item is string=>typeof item==="string"&&ACTIVITY_TYPES.has(item))));
  const maxExercises=Number.isInteger(body.maxExercises)
    ?Math.max(1,Math.min(12,body.maxExercises!)):4;
  if(!format||!["league","groups","cup"].includes(format)||
     allowed.length===0||prompt.length<8||prompt.length>500)
    return json({error:"Skriv et kort mål og velg minst én aktivitet."},400);
  const {data:previous}=await admin.from("athlth_competition_coach_limits")
    .select("last_requested_at").eq("user_id",user.id).maybeSingle();
  if(previous?.last_requested_at &&
     Date.now()-new Date(previous.last_requested_at).getTime()<30000)
    return json({error:"Vent litt før du ber Coach om et nytt forslag."},429);
  await admin.from("athlth_competition_coach_limits").upsert(
    {user_id:user.id,last_requested_at:new Date().toISOString()},
    {onConflict:"user_id"});
  const {data:templates,error:catalogError}=await admin
    .from("athlth_tournament_activity_templates")
    .select("id,title,activity_type")
    .eq("is_active",true).in("activity_type",allowed).limit(100);
  if(catalogError||!templates?.length)
    return json({error:"Øvelsesbiblioteket er utilgjengelig."},503);
  const catalog=templates as CatalogExercise[];
  const catalogIds=new Set(catalog.map(item=>item.id));
  const formatLabel=format==="cup"?"Cup":"Liga";
  const system = [
    "You are ATHLTH Coach. Design a realistic friendly fitness competition draft in Norwegian.",
    "Return only strict JSON, no markdown, with keys:",
    "title (string 3-80), exerciseIDs (array of IDs from the exact catalog below),",
    "startMode (manual or when_ready), environment (any, outdoor, gym),",
    "releaseEvery (integer 1-28), completionHours (24,48,72,168),",
    "allowedRules (string max 350), prohibitedRules (string max 350),",
    "explanation (max 250).",
    "Never invent exercise IDs. Do not guess participants, addresses or dates.",
    "Outdoor only can apply to running/walking/hiking; gym only to strength.",
    "Use up to "+maxExercises+" distinct exercise IDs matching the request.",
    "No health data is provided. Do not include coercive prizes or penalties.",
    "Format: "+formatLabel+". Allowed sports: "+allowed.join(", "),
    "Authoritative exercise catalog: "+JSON.stringify(catalog)
  ].join("\n");
  const signal=AbortSignal.timeout(25000);
  let completion:unknown;
  try {
    const response=await fetch("https://api.groq.com/openai/v1/chat/completions",{
      method:"POST",signal,
      headers:{"Authorization":'Bearer '+groq,"Content-Type":"application/json"},
      body:JSON.stringify({
        model:Deno.env.get("GROQ_TRAINING_MODEL")??"openai/gpt-oss-120b",
        temperature:0.25,max_completion_tokens:750,
        response_format:{type:"json_object"},
        messages:[
          {role:"system",content:system},
          {role:"user",content:"User's competition goal:\n"+prompt}
        ]
      })
    });
    if(!response.ok) return json({error:"Coach kan ikke lage forslag akkurat nå."},503);
    const payload=await response.json();
    completion=JSON.parse(payload?.choices?.[0]?.message?.content??"{}");
  } catch {
    return json({error:"Coach svarte ikke. Prøv på nytt."},503);
  }
  const proposal=completion as Record<string,unknown>;
  const selected=Array.from(new Set(
    (Array.isArray(proposal.exerciseIDs)?proposal.exerciseIDs:[]).filter(
      (id):id is string=>typeof id==="string"&&catalogIds.has(id)
    ))).slice(0,maxExercises);
  if(selected.length===0) selected.push(catalog[0].id);
  const proposedEnvironment=clean(proposal.environment,20);
  const environment=validEnvironment.has(proposedEnvironment) &&
      (proposedEnvironment!=="outdoor"||
       allowed.some(x=>["walking","running","hiking"].includes(x))) &&
      (proposedEnvironment!=="gym"||allowed.includes("strength"))
       ?proposedEnvironment:"any";
  const proposedMode=clean(proposal.startMode,20);
  const count=Number(proposal.releaseEvery);
  const hours=Number(proposal.completionHours);
  return json({
    title:clean(proposal.title,80)||formatLabel+" · ATHLTH",
    exerciseIDs:selected,
    exerciseNames:selected.map(id=>catalog.find(item=>item.id===id)?.title??""),
    startMode:allowedStartModes.has(proposedMode)?proposedMode:"manual",
    environment,
    releaseEvery:Number.isInteger(count)?Math.min(28,Math.max(1,count)):7,
    completionHours:[24,48,72,168].includes(hours)?hours:48,
    allowedRules:clean(proposal.allowedRules,350),
    prohibitedRules:clean(proposal.prohibitedRules,350),
    explanation:clean(proposal.explanation,250)
  });
});
