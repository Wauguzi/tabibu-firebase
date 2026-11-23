/** Kiswahili alert copy: the template segments and the banned phrases. */
export const ALERT_TEMPLATE_SW = {
  headline: 'Tahadhari ya afya: {disease} katika Kaunti ya {county}',
  patientBody:
    'Visa vya {disease} vimethibitishwa katika Kaunti ya {county}. Fuata mwongozo wa Wizara ya Afya ' +
    'hapa chini, na nenda kwenye kituo cha afya ukijisikia vibaya.',
  clinicianBody:
    'Majibu yaliyothibitishwa ya {disease} katika Kaunti ya {county}, wiki ya {weekStart}: ' +
    '{count}. Kuwa macho kwa wanaoshukiwa kuwa na ugonjwa huu na ufuate mwongozo wa Wizara ya ' +
    'Afya hapa chini.',
} as const;

/** Lowercase fragments that diagnose, reassure or predict; any of them fails the draft. */
export const BANNED_SW: readonly string[] = [
  'una ugonjwa',
  'huna ugonjwa',
  'hakuna hatari',
  'hamna hatari',
  'uko salama',
  'mko salama',
  'utapona',
  'itaenea',
  'haitaenea',
  'usijali',
  'msijali',
];
