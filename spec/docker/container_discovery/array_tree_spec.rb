# frozen_string_literal: true

RSpec.describe Docker::ContainerDiscovery::ArrayTree do
  describe '#depth' do
    context 'when empty' do
      it { expect(subject.depth).to eq(0) }
    end

    context 'with leaves' do
      subject do
        s = described_class.new

        s.set('1', 'first')
        s.set('2', 'second')
        s
      end

      it { expect(subject.depth).to eq(1) }
    end

    context 'with branches' do
      subject do
        s = described_class.new

        s.set('1', 'first', 'first', 'first')
        s.set('2', 'second', 'second')
        s
      end

      it { expect(subject.depth).to eq(3) }
    end
  end

  describe '#empty?' do
    context 'when empty' do
      it { expect(subject.empty?).to be(true) }
    end

    context 'with leaves' do
      subject do
        s = described_class.new

        s.set('1', 'first')
        s.set('2', 'second')
        s
      end

      it { expect(subject.empty?).to be(false) }
    end

    context 'with branches' do
      subject do
        s = described_class.new

        s.set('1', 'first', 'first', 'first')
        s.set('2', 'second', 'second')
        s
      end

      it { expect(subject.empty?).to be(false) }
    end

    context 'with empty leaves' do
      subject do
        s = described_class.new

        s.set('1', 'leaf')
        s.remove('1', 'leaf')
        s
      end

      it { expect(subject.empty?).to be(true) }
    end
  end

  describe '#dig' do
    subject do
      s = described_class.new

      s.set('oneDOTthree', '1.1', '1.2', '1.3')
      s.append('oneDOTtwo', '1.1', '1.2')
      s.append('twoDOTtwo', '2.1', '2.2')
      s.append('twoDOTtwo2', '2.1', '2.2')
      s
    end

    it { expect(subject.dig('*', '*')).to contain_exactly(['oneDOTtwo'], %w[twoDOTtwo twoDOTtwo2]) }
    it { expect(subject.dig('1.1', '1.2', '*')).to contain_exactly(['oneDOTthree']) }
    it { expect(subject.dig('1.1', '1.2', '1.3')).to contain_exactly(['oneDOTthree']) }
    it { expect(subject.dig('2.1', '2.2')).to contain_exactly(%w[twoDOTtwo twoDOTtwo2]) }
    it { expect(subject.dig('1.1', '1.2')).to contain_exactly(['oneDOTtwo']) }
    it { expect(subject['2.1']).to contain_exactly([]) }
    it { expect(subject['3.1']).to be_empty }
    it { expect(subject.dig).to contain_exactly([]) }
  end

  describe '#set' do
    context 'using keys' do
      it('replaces the input') do
        expect(subject.dig('1.1', '1.2')).to be_empty
        expect(subject['1.1']).to be_empty
        expect(subject.set('oneDOTtwo', '1.1', '1.2')).to contain_exactly([])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.set('one-two', '1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(['one-two'])
      end
    end

    context 'using wildcards' do
      it('replaces the input') do
        expect(subject.set('oneDOTtwoDOTone', '1.1', '1.2.1')).to contain_exactly([])
        expect(subject.set('oneDOTtwoDOTtwo', '1.1', '1.2.2')).to contain_exactly([])
        expect(subject.set('one-two-*', '1.1', '*')).to contain_exactly(['oneDOTtwoDOTone'], ['oneDOTtwoDOTtwo'])
        expect(subject.dig('1.1', '1.2.1')).to contain_exactly(['one-two-*'])
        expect(subject.dig('1.1', '1.2.2')).to contain_exactly(['one-two-*'])
      end
    end

    context 'no input' do
      it('replaces the input') do
        expect(subject.set('one')).to contain_exactly([])
        expect(subject.set('two')).to contain_exactly(['one'])
        expect(subject.dig).to contain_exactly(['two'])
      end
    end
  end

  describe '#append' do
    context 'using keys' do
      it('appends the input') do
        expect(subject.dig('1.1', '1.2')).to be_empty
        expect(subject['1.1']).to be_empty
        expect(subject.append('oneDOTtwo', '1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.append('one-two', '1.1', '1.2')).to contain_exactly(%w[oneDOTtwo one-two])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(%w[oneDOTtwo one-two])
      end
    end

    context 'using wildcards' do
      it('appends the input') do
        expect(subject.append('oneDOTtwoDOTone', '1.1', '1.2.1')).to contain_exactly(['oneDOTtwoDOTone'])
        expect(subject.append('oneDOTtwoDOTtwo', '1.1', '1.2.2')).to contain_exactly(['oneDOTtwoDOTtwo'])
        expect(subject.append('one-two-*', '1.1', '*')).to contain_exactly(['oneDOTtwoDOTone', 'one-two-*'], ['oneDOTtwoDOTtwo', 'one-two-*'])
        expect(subject.dig('1.1', '1.2.1')).to contain_exactly(['oneDOTtwoDOTone', 'one-two-*'])
        expect(subject.dig('1.1', '1.2.2')).to contain_exactly(['oneDOTtwoDOTtwo', 'one-two-*'])
      end
    end
  end

  describe '#remove' do
    context 'using keys' do
      it('removes the input') do
        expect(subject.dig('1.1', '1.2')).to be_empty
        expect(subject.append('oneDOTtwo', '1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.remove('one-two', '1.1', '1.2')).to contain_exactly([])
        expect(subject.remove('oneDOTtwo', '1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.dig('1.1', '1.2')).to contain_exactly([])
      end
    end

    context 'using wildcards' do
      it('removes the input') do
        expect(subject.set('one', '1.1', '1.2.1')).to contain_exactly([])
        expect(subject.set('one', '1.1', '1.2.2')).to contain_exactly([])
        expect(subject.set('three', '1.1', '1.2.3')).to contain_exactly([])
        expect(subject.remove('one', '1.1', '*')).to contain_exactly(['one'], ['one'], [])
        expect(subject.dig('1.1', '1.2.1')).to contain_exactly([])
        expect(subject.dig('1.1', '1.2.2')).to contain_exactly([])
        expect(subject.dig('1.1', '1.2.3')).to contain_exactly(['three'])
      end
    end
  end

  describe '#delete' do
    context 'using keys' do
      it('deletes the input') do
        expect(subject.dig('1.1', '1.2')).to be_empty
        expect(subject.append('oneDOTtwo', '1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.dig('1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
        expect(subject.delete('1.1', '1.2')).to contain_exactly(['oneDOTtwo'])
      end
    end

    context 'using wildcards' do
      it('deletes the input') do
        expect(subject.set('one', '1.1', '1.2.1')).to contain_exactly([])
        expect(subject.set('two', '1.1', '1.2.2')).to contain_exactly([])
        expect(subject.set('three', '1.1', '1.2.3')).to contain_exactly([])
        expect(subject.delete('1.1', '*')).to contain_exactly(['one'], ['two'], ['three'])
        expect(subject.dig('1.1', '1.2.1')).to be_empty
        expect(subject.dig('1.1', '1.2.2')).to be_empty
        expect(subject.dig('1.1', '1.2.3')).to be_empty
      end
    end

    context 'root wildcard' do
      it('deletes the input') do
        expect(subject.append('one', '1.1', '1.2.1')).to contain_exactly(['one'])
        expect(subject.append('two', '1.1', '1.2.2')).to contain_exactly(['two'])
        expect(subject.append('three', '1.1', '1.2.3')).to contain_exactly(['three'])
        expect(subject.append('four', '1.1')).to contain_exactly(['four'])
        expect(subject.delete('*')).to contain_exactly(['four'])
        expect(subject['1.1']).to be_empty
        expect(subject.dig('1.1', '1.2.1')).to be_empty
        expect(subject.dig('1.1', '1.2.2')).to be_empty
        expect(subject.dig('1.1', '1.2.3')).to be_empty
      end
    end

    context 'no input' do
      it('deletes the input') do
        expect(subject.set('one', '1.1', '1.2.1')).to contain_exactly([])
        expect(subject.set('two', '1.1', '1.2.2')).to contain_exactly([])
        expect(subject.set('three', '1.1', '1.2.3')).to contain_exactly([])
        expect(subject.delete).to be_empty
        expect(subject.dig('1.1', '1.2.1')).to be_empty
        expect(subject.dig('1.1', '1.2.2')).to be_empty
        expect(subject.dig('1.1', '1.2.3')).to be_empty
      end
    end
  end
end
