/* Fusball - configurazione. La chiave "anon" (publishable) e' pubblica per natura: la sicurezza sta nelle policy RLS e nelle funzioni.
   Mai la service_role in questo repository. */
window.FUSBALL = {
  SUPABASE_URL: "https://cgzjdpnhinrmklxlcgza.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_0NCeBMapmyrmC26jq1_m3g_L5a3JvEr",
  SCHEMA: "fusball",
  ELO_START: 1000, ELO_K: 24,
  MIN_COPPIA_PARTITE: 3,          // minimo partite per Migliore/Peggiore coppia e miglior/peggior compagno
  MAX_GOL: 30,
  BADGE: { IN_FIAMME: 5, INARRESTABILE: 10, VETERANO: 50, CENTURIONE: 100,
           DOMINIO_SCARTO: 6, RIMONTA_SOTTO: 4, MURO_MIN_PARTITE: 10, MURO_MEDIA_SUBITI: 6 },
  BACKUP_PROMEMORIA_GIORNI: 7
};
