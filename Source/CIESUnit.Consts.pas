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

  PARAM_FILES = 'Files';
  PARAM_LOG_FILE = 'LogFile';
  PARAM_SIGN_COMMAND = 'SignCommand';
  PARAM_SIGN_FILTER = 'SignFilter';

  SIGN_TIMEOUT_MAX = 86400; // One day

  SIGN_FILE_NAME_PLACEHOLDER = '%filename%';

  // Written to the application folder, when Log is True and LogFile is not given
  LOG_FILE_NAME_DEFAULT = 'IsExeSigned.xml';
  LOG_TEST_SUITE_NAME = 'Signatures';

implementation

end.
