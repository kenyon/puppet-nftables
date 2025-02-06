# frozen_string_literal: true

require 'spec_helper'

describe 'nftables' do
  let(:pre_condition) { 'Exec{path => "/bin"}' }

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      nft_path = case os_facts[:os]['family']
                 when 'Archlinux'
                   '/usr/bin/nft'
                 else
                   '/usr/sbin/nft'
                 end
      nft_config = case os_facts[:os]['family']
                   when 'RedHat'
                     '/etc/sysconfig/nftables.conf'
                   else
                     '/etc/nftables.conf'
                   end

      nft_mode = case os_facts[:os]['family']
                 when 'RedHat'
                   '0600'
                 else
                   '0640'
                 end

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_package('nftables') }

      case [os_facts[:os]['name'], os_facts[:os]['release']['major']]
      when ['Ubuntu', '20.04']
        it { is_expected.to contain_package('netbase') }
      else
        it { is_expected.not_to contain_package('netbase') }
      end

      context 'with clobber_default_config false' do
        let(:params) do
          { clobber_default_config: false }
        end

        it {
          is_expected.to contain_file_line('enable_nftables').with(
            line: 'include "/etc/nftables/puppet.nft"',
            path: nft_config
          )
        }

        it { is_expected.not_to contain_file(nft_config) }
      end

      context 'with clobber_default_config true' do
        let(:params) do
          { clobber_default_config: true }
        end

        it {
          is_expected.to contain_file(nft_config).with(
            ensure: 'file',
            content: %r{^include "/etc/nftables/puppet.nft"$},
            owner: 'root',
            group: 'root'
          )
        }

        it { is_expected.not_to contain_file_line('enable_nftables') }
      end

      it {
        is_expected.to contain_file('/etc/nftables').with(
          ensure: 'directory',
          owner: 'root',
          group: 'root',
          mode: nft_mode
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet.nft').with(
          ensure: 'file',
          owner: 'root',
          group: 'root',
          mode: nft_mode,
          content: %r{flush ruleset}
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet.nft').with(
          content: %r{^include "file-\*\.nft"$}
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet').with(
          ensure: 'directory',
          owner: 'root',
          group: 'root',
          mode: nft_mode,
          purge: true,
          force: true,
          recurse: true
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').with(
          ensure: 'file',
          owner: 'root',
          group: 'root',
          mode: nft_mode,
          content: %r{flush ruleset}
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').with(
          content: %r{^include "file-\*\.nft"$}
        )
      }

      it {
        expect(subject).to contain_file('/etc/nftables/puppet-preflight').with(
          ensure: 'directory',
          owner: 'root',
          group: 'root',
          mode: nft_mode,
          purge: true,
          force: true,
          recurse: true
        )
      }

      it {
        expect(subject).not_to contain_exec('nftables_memory_state_check')
      }

      it {
        expect(subject).not_to contain_exec('nftables_generate_hash')
      }

      it {
        expect(subject).not_to contain_file('/var/tmp/puppet-nft-memhash')
      }

      it {
        expect(subject).to contain_exec('nft validate').with(
          refreshonly: true,
          command: %r{^#{nft_path} -I /etc/nftables/puppet-preflight -c -f /etc/nftables/puppet-preflight.nft.*}
        )
      }

      it {
        expect(subject).to contain_service('nftables').with(
          ensure: 'running',
          enable: true,
          hasrestart: true,
          restart: %r{PATH=/usr/bin:/bin systemctl reload nft.*}
        )
      }

      it {
        expect(subject).to contain_systemd__dropin_file('puppet_nft.conf').with(
          content: %r{^ExecReload=#{nft_path} -I /etc/nftables/puppet -f #{nft_config}$}
        )
      }

      case os_facts[:os]['family']
      when 'Archlinux'

        it {
          expect(subject).to contain_service('firewalld').with(
            ensure: 'stopped',
            enable: false
          )
        }
      when 'Debian'
        it {
          is_expected.to contain_service('firewalld').with(
            ensure: 'stopped',
            enable: false
          )
        }
      else
        it {
          expect(subject).to contain_service('firewalld').with(
            ensure: 'stopped',
            enable: 'mask'
          )
        }
      end

      it { is_expected.to contain_class('nftables::inet_filter') }
      it { is_expected.to contain_class('nftables::ip_nat') }
      it { is_expected.to contain_class('nftables::rules::out::http') }
      it { is_expected.to contain_class('nftables::rules::out::https') }
      it { is_expected.to contain_class('nftables::rules::out::dns') }
      it { is_expected.to contain_class('nftables::rules::out::chrony') }
      it { is_expected.not_to contain_class('nftables::rules::out::all') }
      it { is_expected.not_to contain_nftables__rule('default_out-all') }

      context 'with out_all set true' do
        let(:params) do
          {
            out_all: true,
          }
        end

        it { is_expected.to contain_class('nftables::rules::out::all') }
        it { is_expected.not_to contain_class('nftables::rules::out::http') }
        it { is_expected.not_to contain_class('nftables::rules::out::https') }
        it { is_expected.not_to contain_class('nftables::rules::out::dns') }
        it { is_expected.not_to contain_class('nftables::rules::out::chrony') }
        it { is_expected.to contain_nftables__rule('default_out-all').with_content('accept') }
        it { is_expected.to contain_nftables__rule('default_out-all').with_order('90') }
      end

      context 'with custom rules' do
        let(:params) do
          {
            rules: {
              'INPUT-web_accept' => {
                order: '50',
                content: 'iifname eth0 tcp dport { 80, 443 } accept',
              },
            },
          }
        end

        it {
          expect(subject).to contain_concat__fragment('nftables-inet-filter-chain-INPUT-rule-web_accept').with(
            target: 'nftables-inet-filter-chain-INPUT',
            content: %r{^  iifname eth0 tcp dport \{ 80, 443 \} accept$},
            order: '50-nftables-inet-filter-chain-INPUT-rule-web_accept-b'
          )
        }
      end

      context 'with custom sets' do
        let(:params) do
          {
            sets: {
              'testset1' => {
                type: 'ipv4_addr',
                gc_interval: 2,
              },
              'testset2' => {
                type: 'ipv6_addr',
                elements: ['2a02:62:c601::dead:beef'],
              },
            },
          }
        end

        it {
          expect(subject).to contain_nftables__set('testset1').with(
            type: 'ipv4_addr',
            gc_interval: 2,
            table: 'inet-filter'
          )
        }

        it {
          expect(subject).to contain_nftables__set('testset2').with(
            type: 'ipv6_addr',
            elements: ['2a02:62:c601::dead:beef'],
            table: 'inet-filter'
          )
        }
      end

      context 'without masking firewalld' do
        let(:params) do
          {
            'firewalld_enable' => false,
          }
        end

        it {
          expect(subject).to contain_service('firewalld').with(
            ensure: 'stopped',
            enable: false
          )
        }
      end

      context 'with no default filtering rules' do
        let(:params) do
          {
            'inet_filter' => false,
          }
        end

        it { is_expected.to contain_class('nftables::ip_nat') }
        it { is_expected.not_to contain_class('nftables::inet_filter') }
      end

      context 'with no default tables, chains or rules' do
        let(:params) do
          {
            'inet_filter' => false,
            'nat' => false,
          }
        end

        it { is_expected.not_to contain_class('nftables::ip_nat') }
        it { is_expected.not_to contain_class('nftables::inet_filter') }
        it { is_expected.to have_nftables__config_resource_count(0) }
        it { is_expected.to have_nftables__chain_resource_count(0) }
        it { is_expected.to have_nftables__rule_resource_count(0) }
        it { is_expected.to have_nftables__set_resource_count(0) }
      end

      context 'when purging unmanaged rules' do
        let(:params) do
          {
            'purge_unmanaged_rules' => true,
            'inmem_rules_hash_file' => '/foo/bar',
          }
        end

        it {
          is_expected.to contain_exec('nftables_memory_state_check').with(
            command: %w[echo reloading_nftables],
            notify: 'Service[nftables]',
            unless: ['test -s /foo/bar -a "$(nft -s list ruleset | sha1sum)" = "$(cat /foo/bar)"']
          )
        }

        it {
          is_expected.to contain_exec('nftables_generate_hash').with(
            command: ['nft -s list ruleset | sha1sum > /foo/bar'],
            subscribe: 'Service[nftables]',
            refreshonly: true
          )
        }
      end

      %w[ip ip6 inet arp bridge netdev].each do |family|
        context "with noflush_tables parameter set to valid family #{family}" do
          let(:params) do
            {
              noflush_tables: ["#{family}-f2b-table"],
            }
          end

          context 'with no nftables fact' do
            it { is_expected.to contain_file('/etc/nftables/puppet-preflight.nft').with_content(%r{^flush ruleset$}) }
          end

          context 'with nftables fact matching' do
            let(:facts) do
              super().merge(nftables: { tables: %W[#{family}-abc #{family}-f2b-table] })
            end

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^table #{family} abc \{\}$})
            }

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^flush table #{family} abc$})
            }
          end

          context 'with nftables fact not matching' do
            let(:facts) do
              super().merge(nftables: { tables: %W[#{family}-abc #{family}-ijk] })
            end

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^table #{family} abc \{\}$})
            }

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^flush table #{family} abc$})
            }

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^table #{family} ijk \{\}$})
            }

            it {
              expect(subject).to contain_file('/etc/nftables/puppet-preflight.nft').
                with_content(%r{^flush table #{family} ijk$})
            }
          end
        end
      end

      %w[it ip7 inter arpa brid netdevs].each do |family|
        context "with noflush_tables parameter set to invalid family #{family}" do
          let(:params) do
            {
              noflush_tables: ["#{family}-f2b-table"],
            }
          end

          it { is_expected.not_to compile }
        end
      end
    end
  end
end
