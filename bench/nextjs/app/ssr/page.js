export default function HelloSsr() {
  const arr = new Array(50).fill(1);

  return (
    <main>
      {arr.map((v, i) => (
        <div key={i}>SSR {v}-{i}</div>
      ))}
    </main>
  );
}

export const dynamic = "force-dynamic";