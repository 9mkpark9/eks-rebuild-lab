/** 받침에 따라 조사를 고른다: josa('콩이', '은', '는') → '콩이는' */
export function josa(word: string, withFinal: string, withoutFinal: string) {
  const code = word.charCodeAt(word.length - 1) - 0xac00;
  const hasFinal = code >= 0 && code <= 11171 && code % 28 !== 0;
  return word + (hasFinal ? withFinal : withoutFinal);
}

/** i-0c42e8a1d3f5b7960 → i-0c42…7960 */
export function shortNode(name: string | null) {
  if (!name) return '—';
  const host = name.split('.')[0];
  return host.length > 12 ? `${host.slice(0, 6)}…${host.slice(-4)}` : host;
}
