export default function HelloSsr() {
  const arr = Array.from({ length: 50 }, () => 1);

  return (
    <main>
      {arr.map((v, i) => (
        <div>SSR {v}-{i}</div>
      ))}
    </main>
  );
}

export const dynamic = "force-dynamic";