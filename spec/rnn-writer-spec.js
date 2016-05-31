describe('RNNWriter', () => {
  var rnnWriter;

  beforeEach(() => {
    // create new RNNWriter instance for every test
    rnnWriter = require('../lib/rnn-writer');
  });

  describe('config', () => {
    it('should set the config for the class', () => {
      expect(rnnWriter.config.numberOfSuggestionsPerRequest.order).toEqual(1);
    });
  });

  describe('Method: activate', () => {
    it('should add atom commands to key subscriptions', () => {
      rnnWriter.activate();
      expect(rnnWriter.running).toBe(false);
      expect(rnnWriter.keySubscriptions.disposables.size).toEqual(8);
    });
  });

  describe('Method: toggle', () => {
    describe('already running', () => {
      beforeEach(() => {
        spyOn(rnnWriter, 'showMessage');
        spyOn(rnnWriter, 'reset');
        rnnWriter.running = true;
        rnnWriter.toggle();
      });

      it('should show shut down message if already running', () => {
        expect(rnnWriter.showMessage).toHaveBeenCalledWith('RNN Writer has shut down.');
        expect(rnnWriter.running).toBe(false);
        expect(rnnWriter.reset).toHaveBeenCalledWith('Shutting down for now.');
      });
    });
  });

  describe('Method: deactivate', () => {
    beforeEach(() => {
      spyOn(rnnWriter, 'reset');
      rnnWriter.deactivate();
    });

    it('should call reset', () => {
      expect(rnnWriter.reset).toHaveBeenCalledWith('Deactivated!');
    });
  });

  describe('Method: reset', () => {
    it('should reset necessary attributes', () => {
      rnnWriter.reset('message');

      expect(rnnWriter.suggestions).toEqual([]);
      expect(rnnWriter.suggestionIndex).toEqual(0);
      expect(rnnWriter.currentStartText).toEqual("");
      expect(rnnWriter.currentSuggestionText).toEqual("");
      expect(rnnWriter.offeringSuggestions).toBe(false);
      expect(rnnWriter.changeSuggestionInProgress).toBe(false);
    });

    it('should log the message', () => {
      spyOn(console, 'log');
      rnnWriter.reset('message');

      expect(console.log).toHaveBeenCalledWith('message');
    });
  });
});
