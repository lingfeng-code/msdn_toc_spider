use feature ':5.10';
use Mojo;
use JSON;
use FileHandle;
use Redis::Hash;
use Redis::List;
$ua = Mojo::UserAgent->new;
$ua->inactivity_timeout(60);
$ua->connect_timeout(60);
$ua->request_timeout(60);
$ua->max_connections(1000);
$ua->max_redirects(7);
$ua->transactor->name('Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko');
$ua->cookie_jar->ignore( sub { 1 } );
%hash_url_downloaded = ();
@url_down_list       = ();



# 模块Redis::List.pm     需要添加代码 use Tie::Hash;  事件驱动更改编译模式，不能智能引用未声明的模块



tie( %hash_url_downloaded, 'Redis::Hash', 'hash_name', server => '127.0.0.1:6379' );

#redis-server  启动一个实例
tie( @url_down_list, 'Redis::List', 'list_name', server => '127.0.0.1:6379' );

#列表无法使用
#不支持两个并发数据，列表 基于内部 hash，redis 单线程
#Redis::List 未添加添加 use Tie::Array; 使用单线程，公用一个数据库
$n = 0;

sub url_to_key {
    my $url = $_[0];
    $url =~ s/https:\/\/msdn\.microsoft\.com\/en-us\/library\/|\?toc=1//gi;
    my $key = $url;
    return $key;
}

sub key_to_url {
    my $key = $_[0];
    my $url = "https://msdn.microsoft.com/en-us/library/" . $key . "?toc=1";
    return $url;
}

sub get_single {
    my $url = key_to_url( $_[0] );
    my $tx  = $ua->get($url);
    $n++;
    if ( $tx->error != undef ) {
        say "is error";
        say $url. "\t" . $tx->error->{message};
        my $fh = FileHandle->new(">>error.txt");
        binmode($fh);
        say $fh $url . "\t" . $tx->error->{message};
        $fh->close;
    }
    else {
        my $code = $tx->res->code;
        if ( $code eq "200" ) {
            my $header_size = $tx->res->headers->to_hash->{"Content-Length"};
            my $body_size   = $tx->res->content->body_size;
            if ( $header_size == $body_size and $header_size > 0 ) {
                syswrite STDOUT, "OK\t$n\t" . $url . "\n";
                if ( $tx->result->body =~ m/^\[\{"Title":/m ) {
                    my $perl_hash_or_arrayref = decode_json $tx->result->body;
                    my $i;
                    my $fh = FileHandle->new(">>p-p.txt");
                    binmode($fh);
                    my $fh1 = FileHandle->new(">>name-url.txt");
                    binmode($fh1);
                    my $txt_temp_p_p      = '';
                    my $txt_temp_name_url = '';
                    $txt_temp_p_p = $txt_temp_p_p . $url;

                    foreach $i (@$perl_hash_or_arrayref) {
                        my $href_key;
                        my $href;
                        my $title       = $i->{'Title'};
                        my $deep_switch = $i->{'ExtendedAttributes'}->{'data-tochassubtree'};
                        if ( defined $i->{'Href'} ) {
                            $href_key = url_to_key( $i->{'Href'} );
                            $href     = key_to_url($href_key);
                            unless ( $href_key eq '' ) {
                                unless ( defined $hash_url_downloaded{$href_key} ) {
                                    $hash_url_downloaded{$href_key} = 1;
                                    if (    $deep_switch eq 'true'
                                        and $i->{'Href'} =~ m/^https:\/\/msdn\.microsoft\.com\/en-us\/library\//im )
                                    {
                                        push( @url_down_list, $href_key );
                                    }
                                }
                            }
                        }
                        else {
                            $href_key = "";
                            $href     = "";
                        }
                        $txt_temp_name_url = $txt_temp_name_url . $title . "\t" . $href . "\n";
                        $txt_temp_p_p      = $txt_temp_p_p . "\t" . $href;
                    }
                    $txt_temp_p_p = $txt_temp_p_p . "\n";
                    print $fh1 $txt_temp_name_url;
                    $fh1->close;
                    print $fh $txt_temp_p_p;
                    $fh->close;
                }
            }
            elsif ( $header_size == 0 ) {
                syswrite STDOUT, "OK\t$n\t" . $url . "\n";
            }
            else {
                say "下载不完整\t" . $url;
                push( @url_down_list, $url );
                my $fh = FileHandle->new(">>down_error.txt");
                binmode($fh);
                say $fh "下载不完整\t" . $url;
                $fh->close;
            }
        }
        else {
            say $code. "\t" . $url;
            my $fh = FileHandle->new(">>code_error.txt");
            binmode($fh);
            say $fh $code . "\t" . $url;
            $fh->close;
        }
    }
}

#%hash_url_downloaded @url_down_list  直接使用变量名，不使用地址，会退出
sub get_multiplex {
    my ( $ua, $hash_url_downloaded_ref, $url_down_list_ref ) = @_;
    my $url = key_to_url( shift @$url_down_list_ref );
    unless ( scalar @$url_down_list_ref > 0 ) { return 0 }

    #scalar可能耗时多，连接数据库
    my $delay = Mojo::IOLoop->delay( sub { get_multiplex( $ua, \%hash_url_downloaded, \@url_down_list ) } );
    my $end = $delay->begin;
    $ua->get(
        $url => sub {
            $n++;
            my ( $ua, $tx ) = @_;
            if ( $tx->error != undef ) {
                say "is error";
                say $url. "\t" . $tx->error->{message};
                my $fh = FileHandle->new(">>error.txt");
                binmode($fh);
                say $fh $url . "\t" . $tx->error->{message};
                $fh->close;
            }
            else {
                my $code = $tx->res->code;
                if ( $code eq "200" ) {
                    my $header_size = $tx->res->headers->to_hash->{"Content-Length"};
                    my $body_size   = $tx->res->content->body_size;
                    if ( $header_size == $body_size and $header_size > 0 ) {
                        syswrite STDOUT, "OK\t$n\t" . $url . "\n";
                        if ( $tx->result->body =~ m/^\[\{"Title":/m ) {
                            my $perl_hash_or_arrayref = decode_json $tx->result->body;
                            my $i;
                            my $fh = FileHandle->new(">>p-p.txt");
                            binmode($fh);
                            my $fh1 = FileHandle->new(">>name-url.txt");
                            binmode($fh1);
                            my $txt_temp_p_p      = '';
                            my $txt_temp_name_url = '';
                            $txt_temp_p_p = $txt_temp_p_p . $url;

                            foreach $i (@$perl_hash_or_arrayref) {
                                my $href_key;
                                my $href;
                                my $title       = $i->{'Title'};
                                my $deep_switch = $i->{'ExtendedAttributes'}->{'data-tochassubtree'};
                                if ( defined $i->{'Href'} ) {
                                    $href_key = url_to_key( $i->{'Href'} );
                                    $href     = key_to_url($href_key);
                                    unless ( $href_key eq '' ) {
                                        unless ( defined $hash_url_downloaded_ref->{$href_key} ) {
                                            $hash_url_downloaded_ref->{$href_key} = 1;
                                            if (    $deep_switch eq 'true'
                                                and $i->{'Href'} =~ m/^https:\/\/msdn\.microsoft\.com\/en-us\/library\//im )
                                            {
                                                push( @$url_down_list_ref, $href_key );
                                            }
                                        }
                                    }
                                }
                                else {
                                    $href_key = "";
                                    $href     = "";
                                }
                                $txt_temp_name_url = $txt_temp_name_url . $title . "\t" . $href . "\n";
                                $txt_temp_p_p      = $txt_temp_p_p . "\t" . $href;
                            }
                            $txt_temp_p_p = $txt_temp_p_p . "\n";
                            print $fh1 $txt_temp_name_url;
                            $fh1->close;
                            print $fh $txt_temp_p_p;
                            $fh->close;
                        }
                    }
                    elsif ( $header_size == 0 ) {
                        syswrite STDOUT, "OK\t$n\t" . $url . "\n";
                    }
                    else {
                        say "下载不完整\t" . $url;
                        push( @$url_down_list_ref, $url );
                        my $fh = FileHandle->new(">>down_error.txt");
                        binmode($fh);
                        say $fh "下载不完整\t" . $url;
                        $fh->close;
                    }
                }
                else {
                    say $code. "\t" . $url;
                    my $fh = FileHandle->new(">>code_error.txt");
                    binmode($fh);
                    say $fh $code . "\t" . $url;
                    $fh->close;
                }
            }
            $end->();
        }
    );
}
$hash_url_downloaded{'aa187916.aspx'} = 1;
$hash_url_downloaded{'ms310241'}      = 1;
my $fh1 = FileHandle->new(">>name-url.txt");
binmode($fh1);
my $href  = 'https://msdn.microsoft.com/en-us/library/aa187916.aspx?toc=1';
my $title = 'Development Tools and Languages';
say $fh1 $title . "\t" . $href;
my $href  = 'https://msdn.microsoft.com/en-us/library/ms310241?toc=1';
my $title = 'MSDN Library';
say $fh1 $title . "\t" . $href;
$fh1->close;
get_single('aa187916.aspx');
get_single('ms310241');
map { get_single($_) } @url_down_list;

foreach $i ( 1 .. 200 ) {
    get_multiplex( $ua, \%hash_url_downloaded, \@url_down_list );
}
Mojo::IOLoop->start;

#闭包内    $delay->wait unless $delay->ioloop->is_running; 无法工作
say "下载结束";
sleep 5;
say "剩余地址数量" . scalar(@url_down_list);
my $fh1 = FileHandle->new(">url_lost.txt");
binmode($fh1);
map { say $fh1 $_ } @url_down_list;
$fh1->close;
<STDIN>;
