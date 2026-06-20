async function test() {
  const devRes = await fetch('http://localhost:8080/api/dev/token?user=sam');
  const devJson = await devRes.json();
  const token = devJson.token;
  
  console.log('Token:', token);

  const postRes = await fetch('http://localhost:8080/api/notes', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify({
      title: 'test note',
      preview: 'test preview',
      content: 'test content',
      tags: []
    })
  });
  
  const text = await postRes.text();
  console.log('Status:', postRes.status);
  console.log('Response:', text);
}

test();
