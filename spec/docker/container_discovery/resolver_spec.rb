# frozen_string_literal: true

require 'socket'

RSpec.describe Docker::ContainerDiscovery::Resolver do
  subject do
    formatter = Docker::ContainerDiscovery::LabelFormatter.new('{image.name}.spec')
    logger = double
    allow(logger).to receive(:call)
    allow(logger).to receive(:format_argument)

    described_class.new(formatter, logger,
                        container_cidr: '127.1.2.3/32',
                        advertise_address: '127.2.4.6',
                        advertise_name: 'public',
                        contact: 'contact.name',
                        tld: 'spec.test.',
                        refresh: 123,
                        retry: 456,
                        expire: 789,
                        min_ttl: 101,
                        res_ttl: 112)
  end

  describe '#serial' do
    before do
      allow(Time).to receive(:now).and_return(Time.at(1_234_567_890))
    end

    it do
      expect(subject.serial).to eq(0)
    end
  end

  describe '#name' do
    context 'without arguments' do
      it do
        expect(subject.name).to eq(Resolv::DNS::Name.create('spec.test.'))
      end
    end

    context 'with name' do
      it do
        expect(subject.name('test-case')).to eq(Resolv::DNS::Name.create('test-case.spec.test.'))
      end
    end
  end

  describe '#rev_name' do
    context 'with address' do
      it do
        expect(subject.rev_name('12.34.56.78')).to eq(Resolv::DNS::Name.create('78.56.34.12.in-addr.arpa.'))
      end
    end
  end

  describe '#zone_master' do
    it do
      expect(subject.zone_master).to eq(Resolv::DNS::Name.create('public.spec.test.'))
    end
  end

  describe '#zone_contact' do
    it do
      expect(subject.zone_contact).to eq(Resolv::DNS::Name.create('contact\\.name.spec.test.'))
    end
  end

  describe '#zone_ptr' do
    it do
      expect(subject.zone_ptr).to eq(Resolv::DNS::Name.create('6.4.2.127.in-addr.arpa.'))
    end
  end

  describe '#address' do
    it do
      expect(subject.address).to eq('127.2.4.6')
    end
  end

  describe '#reverse' do
    {
      '12.34.56.78' => '78.56.34.12'
    }.each do |input, output|
      context "using '#{input}'" do
        it do
          expect(subject.reverse(input)).to eq(output)
        end
      end
    end
  end

  describe '#select_address' do
    test_cases = [
      [nil, '192.168.0.128'],
      ['10.1.2.3/24', nil],
      [IPAddr.new('192.168.128.0/24'), '192.168.128.1']
    ]
    mock_addresses = [
      '127.0.0.1',
      '192.168.0.128',
      '192.168.128.1',
      '::1'
    ]

    context 'with pool' do
      let(:pool) { mock_addresses }

      it do
        expect(Socket).not_to receive(:ip_address_list)
        subject.select_address(pool)
      end

      context 'with lazy behaviour' do
        it do
          actual = subject.select_address(pool, '10.1.2.3/32', true)
          expect(actual).to eq('10.1.2.3')
        end

        it do
          actual = subject.select_address(pool, '10.1.2.3/24', true)
          expect(actual).to be_nil
        end
      end

      test_cases.each do |(input, output)|
        it do
          actual = subject.select_address(pool, input)
          expect(actual).to eq(output)
        end
      end
    end

    context 'without pool' do
      before do
        mock_interface_addr = mock_addresses.map do |a|
          Addrinfo.new(Socket.sockaddr_in(53, a))
        end
        allow(Socket).to receive(:ip_address_list).and_return(mock_interface_addr)
      end

      context 'with lazy behaviour' do
        it do
          actual = subject.select_address(nil, '10.1.2.3/32', true)
          expect(actual).to eq('10.1.2.3')
        end

        it do
          actual = subject.select_address(nil, '10.1.2.3/24', true)
          expect(actual).to be_nil
        end
      end

      test_cases.each do |(input, output)|
        it do
          actual = subject.select_address(nil, input)
          expect(actual).to eq(output)
        end
      end
    end
  end
end
