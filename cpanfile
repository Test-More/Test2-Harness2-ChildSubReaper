requires "Exporter" => "0";
requires "XSLoader" => "0";
requires "perl" => "5.014000";
requires "strict" => "0";
requires "warnings" => "0";

on 'test' => sub {
  requires "POSIX" => "0";
  requires "Test2::V0" => "0.000163";
};

on 'configure' => sub {
  requires "ExtUtils::MakeMaker" => "0";
};
