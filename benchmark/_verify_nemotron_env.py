import transformers
print('transformers', transformers.__version__)
try:
    from transformers import AutoModelForRNNT
    print('AutoModelForRNNT OK')
except Exception as e:
    print('AutoModelForRNNT ABSENT:', type(e).__name__, str(e)[:150])
