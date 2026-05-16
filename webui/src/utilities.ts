
const ENKAIDU_URL = window.location.href

export async function enkaidu_get_request(path: string) {
  const request = new Request(new URL(`/api/${path}`, ENKAIDU_URL), {
    method: "GET",
  });

  return await fetch(request);
}

export async function enkaidu_post_request(path: string, content: any) {
  const headers = new Headers({
    "Content-Type": "application/json",
  });

  const request = new Request(new URL(`/api/${path}`, ENKAIDU_URL), {
    method: "POST",
    body: JSON.stringify(content),
    headers: headers,
  });

  return await fetch(request);
}
