unit CIESUnit.Consts;

interface

const
  EXIT_CODE_NOT_SIGNED = 1;
  EXIT_CODE_PARAM_NOT_FOUND = 2;
  EXIT_CODE_PARAM_VALUE_ERROR = 3;
  EXIT_CODE_EXCEPTION = 4;
  EXIT_CODE_SIGNATURE_NOT_VALID = 5;
  EXIT_CODE_SIGN_COMMAND_NO_FILE_NAME = 6;
  EXIT_CODE_SIGN_TIMEOUT = 7;

  PARAM_FILE_NAME = 'FileName';
  PARAM_LOG_FILE_NAME = 'LogFileName';
  PARAM_SIGN_FILE_COMMAND_LINE = 'SignFileCommandLine';
  PARAM_SIGN_FILE_WILD_CARD = 'SignFileWildCard';
  PARAM_SIGN_TIMEOUT = 'SignTimeout';

  SIGN_TIMEOUT_MAX = 86400; // One day

  SIGN_FILE_NAME_PLACEHOLDER = '%filename%';

  // Written to the application folder, when LogToFile is True and LogFileName is not given
  LOG_FILE_NAME_DEFAULT = 'IsExeSigned.xml';
  LOG_TEST_SUITE_NAME = 'Signatures';

implementation

end.
