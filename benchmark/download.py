import truststore; truststore.inject_into_ssl()
import time
from huggingface_hub import snapshot_download
from huggingface_hub.utils import HfHubHTTPError

for r in ['google/gemma-4-E2B-it','google/gemma-4-E4B-it']:
    for attempt in range(1, 9):
        try:
            print(f'[{r}] attempt {attempt}', flush=True)
            snapshot_download(r, ignore_patterns=['*.pth','*.bin','original/*'],
                              max_workers=4, etag_timeout=60)
            print(f'[{r}] DONE', flush=True)
            break
        except Exception as e:
            print(f'[{r}] retry after error: {type(e).__name__} {str(e)[:80]}', flush=True)
            time.sleep(5)
print('ALL DONE', flush=True)
