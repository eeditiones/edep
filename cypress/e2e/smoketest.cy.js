describe('Smoketest', () => {
    it('Can open the edit page', { defaultCommandTimeout: 10000 }, () => {
        cy.visit('edit/demo/E0000028.xml');

        cy.get('.edepid').should('have.value', 'E0000028');

        // There are fragments here
        cy.get('#r-fragments a').should('have.length', '2');

        // We've seen this option list to break in some cases
        cy.get('#findspot-ctrl option')
            .should('have.length.of.at.least', 10)
            .should('not.contain', '{.}')
            .should('not.have.attr', 'value', '{@xml:id}')
            .should('contain', 'A');
    });
});
