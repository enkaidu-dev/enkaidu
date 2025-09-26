
const ENKAIDU_API_BASE_URL = "http://localhost:8765/api"

export async function enkaidu_get_request(path: string) {
  const request = new Request(`${ENKAIDU_API_BASE_URL}/${path}`, {
    method: "GET",
  });

  return await fetch(request);
}

export async function enkaidu_post_request(path: string, content: any) {
  const headers = new Headers({
    "Content-Type": "application/json",
  });

  const request = new Request(`${ENKAIDU_API_BASE_URL}/${path}`, {
    method: "POST",
    body: JSON.stringify(content),
    headers: headers,
  });

  return await fetch(request);
}
