
export async function enkaidu_get_request(path: string) {
  const request = new Request(new URL(`/api/${path}`, window.location.href), {
    method: "GET",
  });

  return await fetch(request);
}

export async function enkaidu_post_request(path: string, content: any) {
  const headers = new Headers({
    "Content-Type": "application/json",
  });

  const request = new Request(new URL(`/api/${path}`, window.location.href), {
    method: "POST",
    body: JSON.stringify(content),
    headers: headers,
  });

  return await fetch(request);
}
