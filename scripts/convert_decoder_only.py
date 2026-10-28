# Runs only the TextDecoder step of whisperkit-generate-model, with the
# correctness threshold lowered: NB-Whisper medium's fp16 decoder lands at
# ~26 dB PSNR against torch, under argmax's 35 dB bar. Word accuracy is
# measured separately on real recordings.
import argparse, os, sys
sys.path.insert(0, os.environ["WHISPERKITTOOLS"])
from argmaxtools import test_utils
from tests import test_text_decoder
test_utils.TEST_PSNR_THR = 20
test_text_decoder.TEST_PSNR_THR = 20
version, out = sys.argv[1], sys.argv[2]
args = argparse.Namespace(
    output_dir=out, model_version=version, test_model_version=version,
    generate_quantized_variants=False, generate_decoder_context_prefill_data=False,
    text_decoder_sdpa_implementation="Cat", sdpa_implementation="Cat",
    text_decoder_max_sequence_length=None, test_seq_len=None, repo_path_suffix=None,
    disable_default_tests=False, upload_results=False, allowed_nbits=[],
    outlier_decomp=False, palettization_group_size=None, force_recipe_nbits=False,
    palettizer_tests=False, context_prefill_tests=False, disable_token_timestamps=False,
    persistent_cache_dir=os.path.join(out, version.replace("/", "_")),
)
test_text_decoder.main(args)
