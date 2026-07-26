interface Badge {
  label: string;
  visible: boolean;
}

export function check(badge: Badge): string {
  return badge.visible ? `${badge.label} が表示されている` : "バッジなし";
}
